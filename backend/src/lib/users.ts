import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { userPreferences, users } from "../db/schema";
import { db } from "./db";

export async function ensureUser(clerkUserId: string) {
  const existing = await db.query.users.findFirst({
    where: eq(users.clerkUserId, clerkUserId),
  });
  if (existing) return { user: existing, created: false as const };

  const [created] = await db
    .insert(users)
    .values({
      id: randomUUID(),
      clerkUserId,
    })
    .onConflictDoNothing({ target: users.clerkUserId })
    .returning();
  if (created) return { user: created, created: true as const };

  const raceSafe = await db.query.users.findFirst({
    where: eq(users.clerkUserId, clerkUserId),
  });
  if (!raceSafe) {
    throw new Error("Unable to ensure user.");
  }
  return { user: raceSafe, created: false as const };
}

export async function ensureUserPreferences(userId: string) {
  const existing = await db.query.userPreferences.findFirst({
    where: eq(userPreferences.userId, userId),
  });
  if (existing) return existing;

  const [created] = await db
    .insert(userPreferences)
    .values({
      id: randomUUID(),
      userId,
    })
    .onConflictDoNothing({ target: userPreferences.userId })
    .returning();
  if (created) return created;

  const raceSafe = await db.query.userPreferences.findFirst({
    where: eq(userPreferences.userId, userId),
  });
  if (!raceSafe) {
    throw new Error("Unable to ensure user preferences.");
  }
  return raceSafe;
}
