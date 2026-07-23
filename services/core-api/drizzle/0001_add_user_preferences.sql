CREATE TABLE IF NOT EXISTS "user_preferences" (
  "id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL,
  "reading_goal" integer DEFAULT 30 NOT NULL,
  "dark_mode" boolean DEFAULT true NOT NULL,
  "notifications_on" boolean DEFAULT true NOT NULL,
  "font_size_pref" text DEFAULT 'medium' NOT NULL,
  "created_at" timestamp DEFAULT now() NOT NULL,
  "updated_at" timestamp DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "user_preferences_user_unique"
  ON "user_preferences" ("user_id");
