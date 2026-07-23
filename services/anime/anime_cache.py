import json
import os
from collections.abc import Callable
from typing import Any

import redis


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
        if cached is not None:
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
            if cached is not None:
                return cached
            value = loader()
            self.set_json(key, value, ttl_seconds)
            return value
        finally:
            try:
                lock.release()
            except redis.exceptions.LockError:
                pass

    def _key(self, key: str) -> str:
        return f"{self.KEY_PREFIX}:{key}"


_cache: AnimeCache | None = None


def anime_cache() -> AnimeCache:
    global _cache
    if _cache is None:
        _cache = AnimeCache.from_environment()
    return _cache
