CREATE TABLE IF NOT EXISTS "media_bookmarks" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "media_type" text NOT NULL,
  "content_id" text NOT NULL,
  "title" text NOT NULL,
  "subtitle" text,
  "image_url" text,
  "is_saved" boolean DEFAULT true NOT NULL,
  "client_updated_at" timestamp with time zone NOT NULL,
  "created_at" timestamp DEFAULT now() NOT NULL,
  "updated_at" timestamp DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "media_bookmark_user_content_unique"
  ON "media_bookmarks" ("user_id", "media_type", "content_id");

CREATE INDEX IF NOT EXISTS "media_bookmark_user_updated_idx"
  ON "media_bookmarks" ("user_id", "updated_at");

CREATE TABLE IF NOT EXISTS "media_playback_progress" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "media_type" text NOT NULL,
  "content_id" text NOT NULL,
  "title" text NOT NULL,
  "image_url" text,
  "unit_id" text NOT NULL,
  "unit_title" text,
  "season_number" integer,
  "episode_number" integer,
  "position_seconds" double precision DEFAULT 0 NOT NULL,
  "duration_seconds" double precision DEFAULT 0 NOT NULL,
  "percentage" double precision DEFAULT 0 NOT NULL,
  "completed" boolean DEFAULT false NOT NULL,
  "client_updated_at" timestamp with time zone NOT NULL,
  "created_at" timestamp DEFAULT now() NOT NULL,
  "updated_at" timestamp DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "media_progress_user_content_unique"
  ON "media_playback_progress" ("user_id", "media_type", "content_id");

CREATE INDEX IF NOT EXISTS "media_progress_user_updated_idx"
  ON "media_playback_progress" ("user_id", "updated_at");

CREATE TABLE IF NOT EXISTS "media_playback_sessions" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "session_id" text NOT NULL,
  "media_type" text NOT NULL,
  "content_id" text NOT NULL,
  "unit_id" text NOT NULL,
  "client_started_at" timestamp with time zone NOT NULL,
  "created_at" timestamp DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "media_session_user_id_unique"
  ON "media_playback_sessions" ("user_id", "session_id");

CREATE INDEX IF NOT EXISTS "media_session_user_started_idx"
  ON "media_playback_sessions" ("user_id", "client_started_at");

CREATE TABLE IF NOT EXISTS "media_viewing_history" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "media_type" text NOT NULL,
  "content_id" text NOT NULL,
  "title" text NOT NULL,
  "image_url" text,
  "unit_id" text NOT NULL,
  "unit_title" text,
  "season_number" integer,
  "episode_number" integer,
  "position_seconds" double precision DEFAULT 0 NOT NULL,
  "duration_seconds" double precision DEFAULT 0 NOT NULL,
  "percentage" double precision DEFAULT 0 NOT NULL,
  "completed" boolean DEFAULT false NOT NULL,
  "visit_count" integer DEFAULT 0 NOT NULL,
  "client_updated_at" timestamp with time zone NOT NULL,
  "first_viewed_at" timestamp with time zone DEFAULT now() NOT NULL,
  "last_viewed_at" timestamp with time zone DEFAULT now() NOT NULL,
  "created_at" timestamp DEFAULT now() NOT NULL,
  "updated_at" timestamp DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "media_history_user_unit_unique"
  ON "media_viewing_history" ("user_id", "media_type", "content_id", "unit_id");

CREATE INDEX IF NOT EXISTS "media_history_user_viewed_idx"
  ON "media_viewing_history" ("user_id", "last_viewed_at", "id");
