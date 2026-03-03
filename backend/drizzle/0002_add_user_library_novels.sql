CREATE TABLE IF NOT EXISTS "user_library_novels" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "novel_id" text NOT NULL,
  "created_at" timestamp DEFAULT now() NOT NULL,
  "updated_at" timestamp DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "user_library_novel_unique"
  ON "user_library_novels" ("user_id", "novel_id");

CREATE INDEX IF NOT EXISTS "user_library_user_created_idx"
  ON "user_library_novels" ("user_id", "created_at");
