import json
import logging
import os
import threading
from collections.abc import Callable
from typing import Any

import redis

logger = logging.getLogger(__name__)


class AnimeCacheError(RuntimeError):
    pass


class AnimeCache:
    KEY_PREFIX = "asterion:anime:v1"
    LOCK_TIMEOUT_SECONDS = 45
    LOCK_WAIT_SECONDS = 30

    def __init__(self, client: redis.Redis):
        self._client = client

    @classmethod
    def from_environment(cls) -> "AnimeCache":
        redis_url = os.environ.get("REDIS_URL", "").strip()
        if not redis_url:
            raise AnimeCacheError("REDIS_URL is required for the anime service.")
        return cls(redis.Redis.from_url(
            redis_url,
            decode_responses=True,
            socket_connect_timeout=3,
            socket_timeout=3,
            health_check_interval=30,
        ))

    def ping(self) -> None:
        try:
            self._client.ping()
        except redis.RedisError as error:
            raise AnimeCacheError("The anime cache is unavailable.") from error

    def get_json(self, key: str) -> Any | None:
        try:
            payload = self._client.get(self._key(key))
        except redis.RedisError as error:
            raise AnimeCacheError("The anime cache could not be read.") from error
        if payload is None:
            return None
        try:
            return json.loads(payload)
        except json.JSONDecodeError as error:
            raise AnimeCacheError("The anime cache contains invalid data.") from error

    def set_json(self, key: str, value: Any, ttl_seconds: int) -> None:
        try:
            self._client.setex(
                self._key(key),
                ttl_seconds,
                json.dumps(value, separators=(",", ":"), ensure_ascii=False),
            )
        except redis.RedisError as error:
            raise AnimeCacheError("The anime cache could not be written.") from error

    def get_or_load(
        self,
        key: str,
        ttl_seconds: int,
        loader: Callable[[], Any],
    ) -> Any:
        cached = self.get_json(key)
        if cached is not None and self._has_fresh_marker(key):
            return cached
        if cached is not None:
            self._spawn_refresh(key, ttl_seconds, loader)
            return cached

        lock = self._client.lock(
            self._key(f"lock:{key}"),
            timeout=self.LOCK_TIMEOUT_SECONDS,
            blocking_timeout=self.LOCK_WAIT_SECONDS,
        )
        try:
            acquired = lock.acquire(blocking=True)
        except redis.RedisError as error:
            raise AnimeCacheError("The anime cache lock is unavailable.") from error
        if not acquired:
            raise AnimeCacheError("The anime request is already taking too long.")

        try:
            cached = self.get_json(key)
            if cached is not None and self._has_fresh_marker(key):
                return cached
            if cached is not None:
                self._spawn_refresh(key, ttl_seconds, loader)
                return cached
            value = loader()
            self._store(key, value, ttl_seconds)
            return value
        finally:
            try:
                lock.release()
            except redis.exceptions.LockError:
                pass

    def _store(self, key: str, value: Any, ttl_seconds: int) -> None:
        self.set_json(key, value, self._stale_ttl(ttl_seconds))
        try:
            self._client.setex(
                self._key(f"{key}:fresh"),
                max(1, int(ttl_seconds)),
                "1",
            )
        except redis.RedisError as error:
            raise AnimeCacheError("The anime cache could not be written.") from error

    def _stale_ttl(self, ttl_seconds: int) -> int:
        return max(int(ttl_seconds) * 7, int(ttl_seconds) + 24 * 60 * 60)

    def _has_fresh_marker(self, key: str) -> bool:
        try:
            return self._client.get(self._key(f"{key}:fresh")) is not None
        except redis.RedisError as error:
            raise AnimeCacheError("The anime cache could not be read.") from error

    def _spawn_refresh(self, key: str, ttl_seconds: int, loader: Callable[[], Any]) -> None:
        def refresh() -> None:
            lock = self._client.lock(
                self._key(f"lock:{key}"),
                timeout=self.LOCK_TIMEOUT_SECONDS,
                blocking_timeout=0,
            )
            try:
                acquired = lock.acquire(blocking=False)
            except redis.RedisError:
                logger.exception("Anime cache refresh lock failed")
                return
            if not acquired:
                return
            try:
                if self._has_fresh_marker(key):
                    return
                value = loader()
                self._store(key, value, ttl_seconds)
            except Exception:
                logger.exception("Anime catalog refresh failed")
            finally:
                try:
                    lock.release()
                except redis.exceptions.LockError:
                    pass

        self._schedule_refresh(refresh)

    @staticmethod
    def _schedule_refresh(work: Callable[[], None]) -> None:
        threading.Thread(target=work, daemon=True).start()

    def _key(self, key: str) -> str:
        return f"{self.KEY_PREFIX}:{key}"


_cache: AnimeCache | None = None


def anime_cache() -> AnimeCache:
    global _cache
    if _cache is None:
        _cache = AnimeCache.from_environment()
    return _cache
