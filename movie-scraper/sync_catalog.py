#!/usr/bin/env python
"""Daily catalog sync: scrapes soap2day → Postgres."""

import os
import sys
import logging
import time
from urllib.parse import urlparse

sys.path.insert(0, os.path.dirname(__file__))

import db
import soap2day

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("sync")


def slug_from_url(url: str) -> str:
    path = urlparse(url).path.strip("/")
    return path.split("/")[-1] if path else ""


def sync_movies():
    logger.info("Syncing movies...")
    total = 0
    start_page = _get_resume_point("movies_sync") + 1
    logger.info("  Starting from page %d", start_page)

    for page in range(start_page, 500):
        try:
            results = soap2day.movies(page)
        except Exception as e:
            logger.warning("Page %d failed: %s", page, str(e))
            time.sleep(5)
            continue

        if not results:
            break

        for r in results:
            slug = r.slug or slug_from_url(r.url)
            db.upsert_movie({
                "imdb_id": r.id or slug, "tmdb_id": None,
                "title": r.title, "slug": slug,
                "overview": None, "poster_url": r.image_url,
                "release_year": r.year, "release_date": None,
                "runtime": None, "budget": None, "revenue": None,
                "tagline": None, "status": None,
                "imdb_rating": float(r.imdb_rating) if r.imdb_rating else None,
                "tmdb_rating": None, "rotten_tomatoes": None, "metacritic": None,
                "director": None, "trailer_url": None,
                "type": r.type or "movie",
                "source_domain": soap2day.BASE,
            })

        total += len(results)
        _set_resume_point("movies_sync", page)
        if page % 10 == 0:
            logger.info("  Page %d, %d total movies synced", page, total)
        time.sleep(0.5)

    logger.info("Movies sync complete: %d total", total)


def sync_tv_shows():
    logger.info("Syncing TV shows...")
    total = 0
    start_page = _get_resume_point("tv_sync") + 1
    logger.info("  Starting from page %d", start_page)
    for page in range(start_page, 120):
        try:
            results = soap2day.tv_shows(page)
        except Exception as e:
            logger.warning("TV page %d failed: %s", page, str(e))
            time.sleep(5)
            continue

        if not results:
            break

        for r in results:
            slug = r.slug or slug_from_url(r.url)
            db.upsert_movie({
                "imdb_id": r.id or slug, "tmdb_id": None,
                "title": r.title, "slug": slug,
                "overview": None, "poster_url": r.image_url,
                "release_year": r.year, "release_date": None,
                "runtime": None, "budget": None, "revenue": None,
                "tagline": None, "status": None,
                "imdb_rating": float(r.imdb_rating) if r.imdb_rating else None,
                "tmdb_rating": None, "rotten_tomatoes": None, "metacritic": None,
                "director": None, "trailer_url": None,
                "type": "tv", "source_domain": soap2day.BASE,
            })

        total += len(results)
        _set_resume_point("tv_sync", page)
        if page % 10 == 0:
            logger.info("  Page %d, %d total TV synced", page, total)
        time.sleep(0.5)

    logger.info("TV sync complete: %d total", total)




def _get_resume_point(task: str) -> int:
    """Get the last completed page for a sync task (stored in DB)."""
    try:
        pg = db.get_pg()
        with pg.cursor() as cur:
            cur.execute("SELECT value FROM sync_progress WHERE task = %s", (task,))
            row = cur.fetchone()
            return int(row[0]) if row else 0
    except Exception:
        return 0


def _set_resume_point(task: str, page: int):
    """Store the current progress page."""
    try:
        pg = db.get_pg()
        with pg.cursor() as cur:
            cur.execute(
                "INSERT INTO sync_progress (task, value) VALUES (%s, %s) "
                "ON CONFLICT (task) DO UPDATE SET value = %s, updated_at = NOW()",
                (task, str(page), str(page)),
            )
    except Exception:
        pass


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--init", action="store_true", help="Initialize schema")
    ap.add_argument("--movies", action="store_true", help="Sync movies")
    ap.add_argument("--tv", action="store_true", help="Sync TV shows")
    ap.add_argument("--all", action="store_true", help="Run all sync steps")
    args = ap.parse_args()

    if args.init or args.all:
        db.init_schema()

    if args.movies or args.all:
        sync_movies()

    if args.tv or args.all:
        sync_tv_shows()

    stats = db.get_catalog_stats()
    logger.info("Catalog: %s", stats)
