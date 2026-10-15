CREATE TABLE IF NOT EXISTS "user_identities" (
  "clerk_user_id" text PRIMARY KEY NOT NULL,
  "user_id" text NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "created_at" timestamp DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS "user_identities_user_id_idx" ON "user_identities" ("user_id");
