import type { FastifyPluginAsync } from "fastify";
import { randomUUID } from "node:crypto";
import { and, countDistinct, desc, eq } from "drizzle-orm";
import { z } from "zod";
import {
  bookmarks,
  readingHistory,
  readingProgress,
  userLibraryNovels,
  userPreferences,
  users,
} from "../db/schema";
import { db } from "../lib/db";
import { ensureUser, ensureUserPreferences } from "../lib/users";

const profilePatchSchema = z.object({
  email: z.string().email().optional(),
  username: z.string().min(1).max(80).optional(),
  avatarUrl: z.string().url().optional(),
});

const upsertProgressSchema = z.object({
  novelId: z.string().min(1),
  chapterId: z.string().min(1),
  currentLine: z.number().int().min(0).default(0),
  totalLines: z.number().int().min(0).default(0),
  percentage: z.number().min(0).max(100).optional(),
});

const bookmarkCreateSchema = z.object({
  novelId: z.string().min(1),
  chapterId: z.string().min(1),
  note: z.string().max(500).optional(),
});

const progressQuerySchema = z.object({
  novelId: z.string().min(1).optional(),
});

const preferencesPatchSchema = z.object({
  readingGoal: z.number().int().min(5).max(100).optional(),
  darkMode: z.boolean().optional(),
  notificationsOn: z.boolean().optional(),
  fontSizePref: z.enum(["small", "medium", "large"]).optional(),
});

const historyQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(50).optional().default(20),
});

const libraryNovelSchema = z.object({
  novelId: z.string().min(1),
});

export const meRoutes: FastifyPluginAsync = async (app) => {
  app.addHook("preHandler", app.authenticate);

  app.get("/me", async (request) => {
    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "GET /me completed.");
    return { data: user };
  });

  app.get("/me/stats", async (request) => {
    const { user } = await ensureUser(request.auth.clerkUserId);

    const [chaptersResult] = await db
      .select({ count: countDistinct(readingHistory.chapterId) })
      .from(readingHistory)
      .where(eq(readingHistory.userId, user.id));

    const progressRows = await db
      .select()
      .from(readingProgress)
      .where(eq(readingProgress.userId, user.id));

    const bookmarkRows = await db
      .select({ id: bookmarks.id })
      .from(bookmarks)
      .where(eq(bookmarks.userId, user.id));

    return {
      data: {
        chaptersRead: chaptersResult?.count ?? 0,
        novelsInProgress: progressRows.length,
        bookmarks: bookmarkRows.length,
      },
    };
  });

  app.patch("/me", async (request, reply) => {
    const parsed = profilePatchSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid profile payload.", issues: parsed.error.flatten() });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const profileData: { email?: string | null; username?: string | null; avatarUrl?: string | null } = {};
    if (parsed.data.email !== undefined) profileData.email = parsed.data.email;
    if (parsed.data.username !== undefined) profileData.username = parsed.data.username;
    if (parsed.data.avatarUrl !== undefined) profileData.avatarUrl = parsed.data.avatarUrl;

    const [updated] = await db
      .update(users)
      .set({
        ...profileData,
        updatedAt: new Date(),
      })
      .where(eq(users.id, user.id))
      .returning();
    if (!updated) {
      return reply.code(404).send({ error: "User not found." });
    }
    app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "PATCH /me completed.");
    return { data: updated };
  });

  app.get("/me/progress", async (request, reply) => {
    const parsed = progressQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid progress query." });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }

    if (parsed.data.novelId) {
      const [progress] = await db
        .select()
        .from(readingProgress)
        .where(and(eq(readingProgress.userId, user.id), eq(readingProgress.novelId, parsed.data.novelId)))
        .limit(1);
      app.log.info(
        { clerkUserId: request.auth.clerkUserId, userId: user.id, novelId: parsed.data.novelId },
        "GET /me/progress by novel completed."
      );
      return { data: progress ?? null };
    }

    const progress = await db
      .select()
      .from(readingProgress)
      .where(eq(readingProgress.userId, user.id))
      .orderBy(desc(readingProgress.updatedAt));
    app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "GET /me/progress completed.");
    return { data: progress };
  });

  app.put("/me/progress", async (request, reply) => {
    const parsed = upsertProgressSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid progress payload.", issues: parsed.error.flatten() });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const percentage =
      parsed.data.percentage ??
      (parsed.data.totalLines > 0
        ? Math.min(100, (parsed.data.currentLine / parsed.data.totalLines) * 100)
        : 0);

    const [upserted] = await db
      .insert(readingProgress)
      .values({
        id: randomUUID(),
        userId: user.id,
        novelId: parsed.data.novelId,
        chapterId: parsed.data.chapterId,
        currentLine: parsed.data.currentLine,
        totalLines: parsed.data.totalLines,
        percentage,
      })
      .onConflictDoUpdate({
        target: [readingProgress.userId, readingProgress.novelId],
        set: {
          chapterId: parsed.data.chapterId,
          currentLine: parsed.data.currentLine,
          totalLines: parsed.data.totalLines,
          percentage,
          updatedAt: new Date(),
        },
      })
      .returning();

    await db.insert(readingHistory).values({
      id: randomUUID(),
      userId: user.id,
      novelId: parsed.data.novelId,
      chapterId: parsed.data.chapterId,
    });

    app.log.info(
      {
        clerkUserId: request.auth.clerkUserId,
        userId: user.id,
        novelId: parsed.data.novelId,
        chapterId: parsed.data.chapterId,
      },
      "PUT /me/progress completed."
    );
    return { data: upserted ?? null };
  });

  app.get("/me/preferences", async (request) => {
    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }

    const prefs = await ensureUserPreferences(user.id);
    return { data: prefs };
  });

  app.patch("/me/preferences", async (request, reply) => {
    const parsed = preferencesPatchSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid preferences payload.", issues: parsed.error.flatten() });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }

    await ensureUserPreferences(user.id);

    const preferenceData: {
      readingGoal?: number;
      darkMode?: boolean;
      notificationsOn?: boolean;
      fontSizePref?: "small" | "medium" | "large";
    } = {};
    if (parsed.data.readingGoal !== undefined) preferenceData.readingGoal = parsed.data.readingGoal;
    if (parsed.data.darkMode !== undefined) preferenceData.darkMode = parsed.data.darkMode;
    if (parsed.data.notificationsOn !== undefined) preferenceData.notificationsOn = parsed.data.notificationsOn;
    if (parsed.data.fontSizePref !== undefined) preferenceData.fontSizePref = parsed.data.fontSizePref;

    const [updated] = await db
      .update(userPreferences)
      .set({
        ...preferenceData,
        updatedAt: new Date(),
      })
      .where(eq(userPreferences.userId, user.id))
      .returning();

    return { data: updated ?? null };
  });

  app.get("/me/history", async (request, reply) => {
    const parsed = historyQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid history query." });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }

    const rows = await db
      .select()
      .from(readingHistory)
      .where(eq(readingHistory.userId, user.id))
      .orderBy(desc(readingHistory.visitedAt))
      .limit(parsed.data.limit);

    app.log.info(
      { clerkUserId: request.auth.clerkUserId, userId: user.id, limit: parsed.data.limit },
      "GET /me/history completed."
    );
    return { data: rows };
  });

  app.get("/me/library", async (request) => {
    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const rows = await db
      .select()
      .from(userLibraryNovels)
      .where(eq(userLibraryNovels.userId, user.id))
      .orderBy(desc(userLibraryNovels.createdAt));
    app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "GET /me/library completed.");
    return { data: rows };
  });

  app.post("/me/library", async (request, reply) => {
    const parsed = libraryNovelSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid library payload.", issues: parsed.error.flatten() });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }

    const [row] = await db
      .insert(userLibraryNovels)
      .values({
        id: randomUUID(),
        userId: user.id,
        novelId: parsed.data.novelId,
      })
      .onConflictDoUpdate({
        target: [userLibraryNovels.userId, userLibraryNovels.novelId],
        set: {
          updatedAt: new Date(),
        },
      })
      .returning();
    app.log.info(
      { clerkUserId: request.auth.clerkUserId, userId: user.id, novelId: parsed.data.novelId },
      "POST /me/library completed."
    );
    return { data: row ?? null };
  });

  app.delete("/me/library/:novelId", async (request, reply) => {
    const params = libraryNovelSchema.safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: "Invalid novel id." });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const deleted = await db
      .delete(userLibraryNovels)
      .where(and(eq(userLibraryNovels.userId, user.id), eq(userLibraryNovels.novelId, params.data.novelId)))
      .returning({ id: userLibraryNovels.id });
    app.log.info(
      {
        clerkUserId: request.auth.clerkUserId,
        userId: user.id,
        novelId: params.data.novelId,
        deleted: deleted.length > 0,
      },
      "DELETE /me/library/:novelId completed."
    );
    return { data: { deleted: deleted.length > 0 } };
  });

  app.get("/me/bookmarks", async (request) => {
    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const rows = await db
      .select()
      .from(bookmarks)
      .where(eq(bookmarks.userId, user.id))
      .orderBy(desc(bookmarks.createdAt));
    app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "GET /me/bookmarks completed.");
    return { data: rows };
  });

  app.post("/me/bookmarks", async (request, reply) => {
    const parsed = bookmarkCreateSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid bookmark payload.", issues: parsed.error.flatten() });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const bookmarkData: { novelId: string; note?: string | null } = {
      novelId: parsed.data.novelId,
    };
    if (parsed.data.note !== undefined) {
      bookmarkData.note = parsed.data.note;
    }
    const bookmarkCreateData: { userId: string; novelId: string; chapterId: string; note?: string | null } = {
      userId: user.id,
      novelId: parsed.data.novelId,
      chapterId: parsed.data.chapterId,
    };
    if (parsed.data.note !== undefined) {
      bookmarkCreateData.note = parsed.data.note;
    }
    const [bookmark] = await db
      .insert(bookmarks)
      .values({
        id: randomUUID(),
        ...bookmarkCreateData,
      })
      .onConflictDoUpdate({
        target: [bookmarks.userId, bookmarks.chapterId],
        set: {
          ...bookmarkData,
          updatedAt: new Date(),
        },
      })
      .returning();
    app.log.info(
      {
        clerkUserId: request.auth.clerkUserId,
        userId: user.id,
        novelId: parsed.data.novelId,
        chapterId: parsed.data.chapterId,
      },
      "POST /me/bookmarks completed."
    );
    return { data: bookmark ?? null };
  });

  app.delete("/me/bookmarks/:id", async (request, reply) => {
    const params = z.object({ id: z.string().min(1) }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: "Invalid bookmark id." });
    }

    const { user, created } = await ensureUser(request.auth.clerkUserId);
    if (created) {
      app.log.info({ clerkUserId: request.auth.clerkUserId, userId: user.id }, "User saved in DB.");
    }
    const deleted = await db
      .delete(bookmarks)
      .where(and(eq(bookmarks.id, params.data.id), eq(bookmarks.userId, user.id)))
      .returning({ id: bookmarks.id });
    app.log.info(
      {
        clerkUserId: request.auth.clerkUserId,
        userId: user.id,
        bookmarkId: params.data.id,
        deleted: deleted.length > 0,
      },
      "DELETE /me/bookmarks/:id completed."
    );
    return { data: { deleted: deleted.length > 0 } };
  });
};
