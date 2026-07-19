-- Movie scraper schema
-- Run: psql $DATABASE_URL -f schema.sql

CREATE TABLE IF NOT EXISTS movies (
    imdb_id TEXT PRIMARY KEY,
    tmdb_id TEXT,
    title TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    overview TEXT,
    poster_url TEXT,
    backdrop_url TEXT,
    release_year TEXT,
    release_date TEXT,
    runtime INTEGER,
    budget BIGINT,
    revenue BIGINT,
    tagline TEXT,
    status TEXT,
    imdb_rating REAL,
    tmdb_rating REAL,
    rotten_tomatoes TEXT,
    metacritic TEXT,
    director TEXT,
    trailer_url TEXT,
    type TEXT NOT NULL DEFAULT 'movie',
    source_domain TEXT,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS genres (
    slug TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS movie_genres (
    imdb_id TEXT NOT NULL REFERENCES movies(imdb_id) ON DELETE CASCADE,
    genre_slug TEXT NOT NULL REFERENCES genres(slug) ON DELETE CASCADE,
    PRIMARY KEY (imdb_id, genre_slug)
);

CREATE TABLE IF NOT EXISTS cast_members (
    id SERIAL PRIMARY KEY,
    imdb_id TEXT NOT NULL REFERENCES movies(imdb_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    character_name TEXT,
    photo_url TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE (imdb_id, name)
);

CREATE TABLE IF NOT EXISTS crew_members (
    id SERIAL PRIMARY KEY,
    imdb_id TEXT NOT NULL REFERENCES movies(imdb_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    job TEXT NOT NULL,
    department TEXT,
    photo_url TEXT,
    UNIQUE (imdb_id, name, job)
);

CREATE TABLE IF NOT EXISTS seasons (
    id SERIAL PRIMARY KEY,
    imdb_id TEXT NOT NULL REFERENCES movies(imdb_id) ON DELETE CASCADE,
    season_number INTEGER NOT NULL,
    title TEXT,
    episode_count INTEGER DEFAULT 0,
    UNIQUE (imdb_id, season_number)
);

CREATE TABLE IF NOT EXISTS episodes (
    id SERIAL PRIMARY KEY,
    season_id INTEGER REFERENCES seasons(id) ON DELETE CASCADE,
    imdb_id TEXT NOT NULL REFERENCES movies(imdb_id) ON DELETE CASCADE,
    episode_number INTEGER NOT NULL,
    title TEXT,
    slug TEXT,
    UNIQUE (imdb_id, episode_number)
);

CREATE INDEX IF NOT EXISTS idx_movies_slug ON movies(slug);
CREATE INDEX IF NOT EXISTS idx_movies_type ON movies(type);
CREATE INDEX IF NOT EXISTS idx_movies_imdb_rating ON movies(imdb_rating DESC);
CREATE INDEX IF NOT EXISTS idx_movies_release_year ON movies(release_year);
CREATE INDEX IF NOT EXISTS idx_cast_members_imdb ON cast_members(imdb_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_seasons_imdb ON seasons(imdb_id);
CREATE INDEX IF NOT EXISTS idx_episodes_imdb ON episodes(imdb_id, episode_number);
