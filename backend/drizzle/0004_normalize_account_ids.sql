ALTER TABLE "user_bookmarks" DROP CONSTRAINT IF EXISTS "user_bookmarks_user_id_fkey";
ALTER TABLE "user_library" DROP CONSTRAINT IF EXISTS "user_library_user_id_fkey";
ALTER TABLE "user_preferences" DROP CONSTRAINT IF EXISTS "user_preferences_user_id_fkey";
ALTER TABLE "user_reading_history" DROP CONSTRAINT IF EXISTS "user_reading_history_user_id_fkey";
ALTER TABLE "user_reading_progress" DROP CONSTRAINT IF EXISTS "user_reading_progress_user_id_fkey";
ALTER TABLE "reading_progress" DROP CONSTRAINT IF EXISTS "reading_progress_user_id_fkey";
ALTER TABLE "bookmarks" DROP CONSTRAINT IF EXISTS "bookmarks_user_id_fkey";
ALTER TABLE "reading_history" DROP CONSTRAINT IF EXISTS "reading_history_user_id_fkey";
ALTER TABLE "user_library_novels" DROP CONSTRAINT IF EXISTS "user_library_novels_user_id_fkey";
ALTER TABLE "media_bookmarks" DROP CONSTRAINT IF EXISTS "media_bookmarks_user_id_fkey";
ALTER TABLE "media_playback_progress" DROP CONSTRAINT IF EXISTS "media_playback_progress_user_id_fkey";
ALTER TABLE "media_playback_sessions" DROP CONSTRAINT IF EXISTS "media_playback_sessions_user_id_fkey";
ALTER TABLE "media_viewing_history" DROP CONSTRAINT IF EXISTS "media_viewing_history_user_id_fkey";

ALTER TABLE "users" ALTER COLUMN "id" DROP DEFAULT;
ALTER TABLE "users" ALTER COLUMN "id" TYPE text USING "id"::text;

ALTER TABLE "user_preferences" ALTER COLUMN "id" DROP DEFAULT;
ALTER TABLE "user_preferences" ALTER COLUMN "id" TYPE text USING "id"::text;
ALTER TABLE "user_preferences" ALTER COLUMN "user_id" TYPE text USING "user_id"::text;
ALTER TABLE "user_bookmarks" ALTER COLUMN "user_id" TYPE text USING "user_id"::text;
ALTER TABLE "user_library" ALTER COLUMN "user_id" TYPE text USING "user_id"::text;
ALTER TABLE "user_reading_history" ALTER COLUMN "user_id" TYPE text USING "user_id"::text;
ALTER TABLE "user_reading_progress" ALTER COLUMN "user_id" TYPE text USING "user_id"::text;

ALTER TABLE "user_preferences" ALTER COLUMN "reading_goal" SET DEFAULT 30;
ALTER TABLE "user_preferences" ALTER COLUMN "dark_mode" SET DEFAULT true;
ALTER TABLE "user_preferences" ALTER COLUMN "notifications_on" SET DEFAULT true;

ALTER SEQUENCE IF EXISTS "users_id_seq" OWNED BY NONE;
ALTER SEQUENCE IF EXISTS "user_preferences_id_seq" OWNED BY NONE;
DROP SEQUENCE IF EXISTS "users_id_seq";
DROP SEQUENCE IF EXISTS "user_preferences_id_seq";

ALTER TABLE "user_bookmarks"
  ADD CONSTRAINT "user_bookmarks_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "user_library"
  ADD CONSTRAINT "user_library_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "user_preferences"
  ADD CONSTRAINT "user_preferences_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "user_reading_history"
  ADD CONSTRAINT "user_reading_history_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "user_reading_progress"
  ADD CONSTRAINT "user_reading_progress_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "reading_progress"
  ADD CONSTRAINT "reading_progress_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "bookmarks"
  ADD CONSTRAINT "bookmarks_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "reading_history"
  ADD CONSTRAINT "reading_history_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "user_library_novels"
  ADD CONSTRAINT "user_library_novels_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "media_bookmarks"
  ADD CONSTRAINT "media_bookmarks_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "media_playback_progress"
  ADD CONSTRAINT "media_playback_progress_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "media_playback_sessions"
  ADD CONSTRAINT "media_playback_sessions_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE "media_viewing_history"
  ADD CONSTRAINT "media_viewing_history_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
