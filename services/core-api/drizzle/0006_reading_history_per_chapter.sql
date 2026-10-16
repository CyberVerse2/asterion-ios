-- One reading_history row per (user, novel, chapter), so clients can upload
-- chapters read offline (POST /me/history) and replays stay idempotent.
-- Until now every progress save appended a row, so collapse those first.

-- Hold off writers (old API containers during a deploy) until the unique
-- index exists; reads keep working. Released at COMMIT.
LOCK TABLE "reading_history" IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE "reading_history" ADD COLUMN IF NOT EXISTS "chapter_number" integer;
ALTER TABLE "reading_history" ADD COLUMN IF NOT EXISTS "chapter_title" text;
ALTER TABLE "reading_history" ADD COLUMN IF NOT EXISTS "progress" double precision DEFAULT 0 NOT NULL;

-- The row kept for each chapter is its latest visit; give it the chapter's
-- earliest created_at so "first read" survives the collapse.
UPDATE "reading_history" AS kept
SET "created_at" = chapter."first_created_at"
FROM (
  SELECT "user_id", "novel_id", "chapter_id", min("created_at") AS "first_created_at"
  FROM "reading_history"
  GROUP BY "user_id", "novel_id", "chapter_id"
  HAVING count(*) > 1
) AS chapter
WHERE kept."user_id" = chapter."user_id"
  AND kept."novel_id" = chapter."novel_id"
  AND kept."chapter_id" = chapter."chapter_id"
  AND kept."created_at" > chapter."first_created_at";

DELETE FROM "reading_history" AS history
USING (
  SELECT "id",
    row_number() OVER (
      PARTITION BY "user_id", "novel_id", "chapter_id"
      ORDER BY "visited_at" DESC, "id" DESC
    ) AS "rank"
  FROM "reading_history"
) AS ranked
WHERE history."id" = ranked."id"
  AND ranked."rank" > 1;

-- The saved position's chapter is as far as the reader got in it.
UPDATE "reading_history" AS history
SET "progress" = least(100, greatest(0, progress."percentage"))
FROM "reading_progress" AS progress
WHERE history."user_id" = progress."user_id"
  AND history."novel_id" = progress."novel_id"
  AND history."chapter_id" = progress."chapter_id"
  AND progress."percentage" <> 'NaN'::double precision
  AND history."progress" < progress."percentage";

CREATE UNIQUE INDEX IF NOT EXISTS "reading_history_user_chapter_unique"
  ON "reading_history" ("user_id", "novel_id", "chapter_id");
