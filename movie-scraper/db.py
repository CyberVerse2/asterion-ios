"""Database layer — Postgres for catalog, Redis for cache."""

import json
import logging
import os
from typing import Optional

import psycopg2
import psycopg2.extras
import redis

logger = logging.getLogger(__name__)

# --- Connection pools ---

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/movies?schema=public")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

_pg_pool: Optional[psycopg2.extensions.connection] = None
_redis: Optional[redis.Redis] = None


def get_pg():
    global _pg_pool
    if _pg_pool is None or _pg_pool.closed:
        _pg_pool = psycopg2.connect(DATABASE_URL)
        _pg_pool.autocommit = True
        psycopg2.extras.register_uuid()
    return _pg_pool


def get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.Redis.from_url(REDIS_URL, decode_responses=True)
    return _redis


# --- Redis cache helpers ---

REDIS_METADATA_TTL = 30 * 24 * 3600  # 30 days
REDIS_STREAMS_TTL = 2 * 3600  # 2 hours (tokens refresh frequently)


def cache_get(key: str) -> Optional[dict]:
    try:
        data = get_redis().get(key)
        return json.loads(data) if data else None
    except Exception:
        return None


def cache_set(key: str, value: dict, ttl: int):
    try:
        get_redis().setex(key, ttl, json.dumps(value))
    except Exception:
        pass


# --- Movie queries ---


def get_movie_by_slug(slug: str) -> Optional[dict]:
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM movies WHERE slug = %s", (slug,))
        row = cur.fetchone()
        if not row:
            return None
        movie = dict(row)
        movie["added_at"] = movie["added_at"].isoformat() if movie.get("added_at") else None
        movie["updated_at"] = movie["updated_at"].isoformat() if movie.get("updated_at") else None

        # Genres
        cur.execute(
            "SELECT g.slug, g.name FROM genres g "
            "JOIN movie_genres mg ON g.slug = mg.genre_slug "
            "WHERE mg.imdb_id = %s ORDER BY g.name",
            (movie["imdb_id"],),
        )
        movie["genres"] = [dict(r) for r in cur.fetchall()]

        # Cast
        cur.execute(
            "SELECT name, character_name, photo_url FROM cast_members "
            "WHERE imdb_id = %s ORDER BY sort_order LIMIT 20",
            (movie["imdb_id"],),
        )
        movie["cast"] = [dict(r) for r in cur.fetchall()]

        return movie


def get_movie_list(page: int = 1, per_page: int = 30, media_type: str = "movie") -> dict:
    offset = (page - 1) * per_page
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT COUNT(*) as total FROM movies WHERE type = %s", (media_type,))
        total = cur.fetchone()["total"]

        cur.execute(
            "SELECT imdb_id, tmdb_id, title, slug, poster_url, release_year, "
            "runtime, imdb_rating, type FROM movies "
            "WHERE type = %s ORDER BY added_at DESC LIMIT %s OFFSET %s",
            (media_type, per_page, offset),
        )
        results = []
        for row in cur.fetchall():
            r = dict(row)
            r["imdb_rating"] = str(r["imdb_rating"]) if r.get("imdb_rating") else None
            r["image_url"] = r.pop("poster_url", None)
            r["url"] = f"https://uk-soap2day.day/{r['slug']}/"
            results.append(r)

        return {
            "page": page,
            "total_pages": max(1, (total + per_page - 1) // per_page),
            "total": total,
            "results": results,
        }


def search_movies(query: str, page: int = 1, per_page: int = 30) -> dict:
    offset = (page - 1) * per_page
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        like = f"%{query}%"
        cur.execute(
            "SELECT COUNT(*) as total FROM movies WHERE title ILIKE %s",
            (like,),
        )
        total = cur.fetchone()["total"]

        cur.execute(
            "SELECT imdb_id, tmdb_id, title, slug, poster_url, release_year, "
            "runtime, imdb_rating, type FROM movies "
            "WHERE title ILIKE %s ORDER BY imdb_rating DESC NULLS LAST "
            "LIMIT %s OFFSET %s",
            (like, per_page, offset),
        )
        results = []
        for row in cur.fetchall():
            r = dict(row)
            r["imdb_rating"] = str(r["imdb_rating"]) if r.get("imdb_rating") else None
            r["image_url"] = r.pop("poster_url", None)
            r["url"] = f"https://uk-soap2day.day/{r['slug']}/"
            results.append(r)

        return {
            "page": page,
            "total_pages": max(1, (total + per_page - 1) // per_page),
            "total": total,
            "results": results,
        }


def get_genres() -> list[dict]:
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT slug, name as title FROM genres ORDER BY name")
        return [dict(r) for r in cur.fetchall()]


def get_popular(media_type: str = "movie", limit: int = 50) -> dict:
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT imdb_id, tmdb_id, title, slug, poster_url, release_year, "
            "runtime, imdb_rating, type FROM movies "
            "WHERE type = %s AND imdb_rating IS NOT NULL "
            "ORDER BY imdb_rating DESC LIMIT %s",
            (media_type, limit),
        )
        results = []
        for row in cur.fetchall():
            r = dict(row)
            r["imdb_rating"] = str(r["imdb_rating"]) if r.get("imdb_rating") else None
            r["image_url"] = r.pop("poster_url", None)
            r["url"] = f"https://uk-soap2day.day/{r['slug']}/"
            results.append(r)
        return {"results": results, "total_pages": 1, "total": len(results)}


# --- Upsert helpers (used by cron sync) ---


def upsert_movie(data: dict):
    pg = get_pg()
    with pg.cursor() as cur:
        # Find existing by slug first (card sync uses temporary imdb_ids)
        cur.execute("SELECT imdb_id FROM movies WHERE slug = %s", (data["slug"],))
        existing = cur.fetchone()
        if existing and data.get("imdb_id") and data["imdb_id"] != existing[0]:
            # Update imdb_id on existing row
            cur.execute("UPDATE movies SET imdb_id = %s WHERE slug = %s",
                       (data["imdb_id"], data["slug"]))

        cur.execute(
            """INSERT INTO movies (imdb_id, tmdb_id, title, slug, overview, poster_url,
               release_year, release_date, runtime, budget, revenue, tagline, status,
               imdb_rating, tmdb_rating, rotten_tomatoes, metacritic, director,
               trailer_url, type, source_domain, updated_at)
            VALUES (%(imdb_id)s, %(tmdb_id)s, %(title)s, %(slug)s, %(overview)s, %(poster_url)s,
               %(release_year)s, %(release_date)s, %(runtime)s, %(budget)s, %(revenue)s,
               %(tagline)s, %(status)s, %(imdb_rating)s, %(tmdb_rating)s,
               %(rotten_tomatoes)s, %(metacritic)s, %(director)s,
               %(trailer_url)s, %(type)s, %(source_domain)s, NOW())
            ON CONFLICT (slug) DO UPDATE SET
               imdb_id = COALESCE(EXCLUDED.imdb_id, movies.imdb_id),
               title = COALESCE(EXCLUDED.title, movies.title),
               overview = COALESCE(EXCLUDED.overview, movies.overview),
               poster_url = COALESCE(EXCLUDED.poster_url, movies.poster_url),
               release_year = COALESCE(EXCLUDED.release_year, movies.release_year),
               imdb_rating = COALESCE(EXCLUDED.imdb_rating, movies.imdb_rating),
               runtime = COALESCE(EXCLUDED.runtime, movies.runtime),
               director = COALESCE(EXCLUDED.director, movies.director),
               tmdb_rating = COALESCE(EXCLUDED.tmdb_rating, movies.tmdb_rating),
               rotten_tomatoes = COALESCE(EXCLUDED.rotten_tomatoes, movies.rotten_tomatoes),
               metacritic = COALESCE(EXCLUDED.metacritic, movies.metacritic),
               source_domain = EXCLUDED.source_domain,
               updated_at = NOW()""",
            data,
        )


def upsert_genres(imdb_id: str, genres: list[dict]):
    pg = get_pg()
    with pg.cursor() as cur:
        # Ensure genres exist
        for g in genres:
            cur.execute(
                "INSERT INTO genres (slug, name) VALUES (%s, %s) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name",
                (g["slug"], g["name"]),
            )
        # Clear existing associations
        cur.execute("DELETE FROM movie_genres WHERE imdb_id = %s", (imdb_id,))
        # Add new associations
        for g in genres:
            cur.execute(
                "INSERT INTO movie_genres (imdb_id, genre_slug) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (imdb_id, g["slug"]),
            )


def upsert_cast(imdb_id: str, cast_list: list[dict]):
    pg = get_pg()
    with pg.cursor() as cur:
        cur.execute("DELETE FROM cast_members WHERE imdb_id = %s", (imdb_id,))
        for i, c in enumerate(cast_list):
            cur.execute(
                "INSERT INTO cast_members (imdb_id, name, character_name, photo_url, sort_order) "
                "VALUES (%s, %s, %s, %s, %s)",
                (imdb_id, c["name"], c.get("character"), c.get("photo"), i),
            )


def upsert_crew(imdb_id: str, crew_list: list[dict]):
    pg = get_pg()
    with pg.cursor() as cur:
        cur.execute("DELETE FROM crew_members WHERE imdb_id = %s", (imdb_id,))
        for c in crew_list:
            cur.execute(
                "INSERT INTO crew_members (imdb_id, name, job, department, photo_url) "
                "VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING",
                (imdb_id, c["name"], c["job"], c.get("department"), c.get("photo")),
            )


def get_by_genre(genre_slug: str, page: int = 1, per_page: int = 30) -> dict:
    offset = (page - 1) * per_page
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT COUNT(*) as total FROM movies m "
            "JOIN movie_genres mg ON m.imdb_id = mg.imdb_id "
            "WHERE mg.genre_slug = %s",
            (genre_slug,),
        )
        total = cur.fetchone()["total"]

        cur.execute(
            "SELECT m.imdb_id, m.tmdb_id, m.title, m.slug, m.poster_url, "
            "m.release_year, m.runtime, m.imdb_rating, m.type FROM movies m "
            "JOIN movie_genres mg ON m.imdb_id = mg.imdb_id "
            "WHERE mg.genre_slug = %s ORDER BY m.imdb_rating DESC NULLS LAST "
            "LIMIT %s OFFSET %s",
            (genre_slug, per_page, offset),
        )
        results = []
        for row in cur.fetchall():
            r = dict(row)
            r["imdb_rating"] = str(r["imdb_rating"]) if r.get("imdb_rating") else None
            r["image_url"] = r.pop("poster_url", None)
            r["url"] = f"https://uk-soap2day.day/{r['slug']}/"
            results.append(r)
        return {
            "page": page,
            "total_pages": max(1, (total + per_page - 1) // per_page),
            "total": total,
            "results": results,
        }


def get_catalog_stats() -> dict:
    pg = get_pg()
    with pg.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT type, COUNT(*) as count FROM movies GROUP BY type")
        rows = {r["type"]: r["count"] for r in cur.fetchall()}
        return {
            "movies": rows.get("movie", 0),
            "tv_shows": rows.get("tv", 0),
            "total": sum(rows.values()),
        }


def init_schema():
    """Run schema.sql to create tables."""
    schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    with open(schema_path) as f:
        sql = f.read()
    pg = get_pg()
    with pg.cursor() as cur:
        cur.execute(sql)
    logger.info("Schema initialized")
