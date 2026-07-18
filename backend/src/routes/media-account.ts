import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { and, desc, eq, sql } from "drizzle-orm";
import { z } from "zod";
import {
  mediaBookmarks,
  mediaPlaybackProgress,
  mediaViewingHistory,
} from "../db/schema";
import { db } from "../lib/db";
import { summarizeMediaAccount } from "../lib/media-account";
import { ensureUser } from "../lib/users";

const mediaTypeSchema = z.enum(["anime", "movie", "football"]);
const playbackMediaTypeSchema = z.enum(["anime", "movie"]);

const bookmarkSchema = z.object({
  mediaType: mediaTypeSchema,
  contentId: z.string().trim().min(1).max(500),
  title: z.string().trim().min(1).max(500),
  subtitle: z.string().trim().max(500).nullable().optional(),
  imageUrl: z.string().url().nullable().optional(),
});

const bookmarkDeleteSchema = z.object({
  mediaType: mediaTypeSchema,
  contentId: z.string().trim().min(1).max(500),
});

const progressSchema = z.object({
  mediaType: playbackMediaTypeSchema,
  contentId: z.string().trim().min(1).max(500),
  title: z.string().trim().min(1).max(500),
  imageUrl: z.string().url().nullable().optional(),
  unitId: z.string().trim().min(1).max(500).nullable().optional(),
  unitTitle: z.string().trim().max(500).nullable().optional(),
  seasonNumber: z.number().int().min(0).nullable().optional(),
  episodeNumber: z.number().int().min(0).nullable().optional(),
  positionSeconds: z.number().finite().min(0),
  durationSeconds: z.number().finite().min(0),
  completed: z.boolean().optional(),
  started: z.boolean().optional().default(false),
});

export function registerMediaAccountRoutes(app: FastifyInstance) {
  app.get("/me/media", async (request) => {
    const { user } = await ensureUser(request.auth.clerkUserId);
    const snapshot = await loadMediaSnapshot(user.id);
    return { data: snapshot };
  });

  app.put("/me/media/bookmarks", async (request, reply) => {
    const parsed = bookmarkSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid media bookmark payload.",
        issues: parsed.error.flatten(),
      });
    }

    const { user } = await ensureUser(request.auth.clerkUserId);
    const [bookmark] = await db
      .insert(mediaBookmarks)
      .values({
        id: randomUUID(),
        userId: user.id,
        mediaType: parsed.data.mediaType,
        contentId: parsed.data.contentId,
        title: parsed.data.title,
        subtitle: parsed.data.subtitle ?? null,
        imageUrl: parsed.data.imageUrl ?? null,
      })
      .onConflictDoUpdate({
        target: [mediaBookmarks.userId, mediaBookmarks.mediaType, mediaBookmarks.contentId],
        set: {
          title: parsed.data.title,
          subtitle: parsed.data.subtitle ?? null,
          imageUrl: parsed.data.imageUrl ?? null,
          updatedAt: new Date(),
        },
      })
      .returning();

    return { data: bookmark ?? null };
  });

  app.delete("/me/media/bookmarks", async (request, reply) => {
    const parsed = bookmarkDeleteSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid media bookmark identifier." });
    }

    const { user } = await ensureUser(request.auth.clerkUserId);
    const deleted = await db
      .delete(mediaBookmarks)
      .where(and(
        eq(mediaBookmarks.userId, user.id),
        eq(mediaBookmarks.mediaType, parsed.data.mediaType),
        eq(mediaBookmarks.contentId, parsed.data.contentId)
      ))
      .returning({ id: mediaBookmarks.id });

    return { data: { deleted: deleted.length > 0 } };
  });

  app.put("/me/media/progress", async (request, reply) => {
    const parsed = progressSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid media progress payload.",
        issues: parsed.error.flatten(),
      });
    }

    const { user } = await ensureUser(request.auth.clerkUserId);
    const positionSeconds = Math.min(
      parsed.data.positionSeconds,
      parsed.data.durationSeconds > 0
        ? parsed.data.durationSeconds
        : parsed.data.positionSeconds
    );
    const percentage = parsed.data.durationSeconds > 0
      ? Math.min(100, (positionSeconds / parsed.data.durationSeconds) * 100)
      : 0;
    const completed = parsed.data.completed ?? percentage >= 90;
    const unitId = parsed.data.unitId ?? parsed.data.contentId;
    const now = new Date();

    const result = await db.transaction(async (tx) => {
      const [progress] = await tx
        .insert(mediaPlaybackProgress)
        .values({
          id: randomUUID(),
          userId: user.id,
          mediaType: parsed.data.mediaType,
          contentId: parsed.data.contentId,
          title: parsed.data.title,
          imageUrl: parsed.data.imageUrl ?? null,
          unitId,
          unitTitle: parsed.data.unitTitle ?? null,
          seasonNumber: parsed.data.seasonNumber ?? null,
          episodeNumber: parsed.data.episodeNumber ?? null,
          positionSeconds,
          durationSeconds: parsed.data.durationSeconds,
          percentage,
          completed,
        })
        .onConflictDoUpdate({
          target: [
            mediaPlaybackProgress.userId,
            mediaPlaybackProgress.mediaType,
            mediaPlaybackProgress.contentId,
          ],
          set: {
            title: parsed.data.title,
            imageUrl: parsed.data.imageUrl ?? null,
            unitId,
            unitTitle: parsed.data.unitTitle ?? null,
            seasonNumber: parsed.data.seasonNumber ?? null,
            episodeNumber: parsed.data.episodeNumber ?? null,
            positionSeconds,
            durationSeconds: parsed.data.durationSeconds,
            percentage,
            completed,
            updatedAt: now,
          },
        })
        .returning();

      const visitCount = parsed.data.started
        ? sql`${mediaViewingHistory.visitCount} + 1`
        : mediaViewingHistory.visitCount;
      const [history] = await tx
        .insert(mediaViewingHistory)
        .values({
          id: randomUUID(),
          userId: user.id,
          mediaType: parsed.data.mediaType,
          contentId: parsed.data.contentId,
          title: parsed.data.title,
          imageUrl: parsed.data.imageUrl ?? null,
          unitId,
          unitTitle: parsed.data.unitTitle ?? null,
          seasonNumber: parsed.data.seasonNumber ?? null,
          episodeNumber: parsed.data.episodeNumber ?? null,
          positionSeconds,
          durationSeconds: parsed.data.durationSeconds,
          percentage,
          completed,
          lastViewedAt: now,
        })
        .onConflictDoUpdate({
          target: [
            mediaViewingHistory.userId,
            mediaViewingHistory.mediaType,
            mediaViewingHistory.contentId,
            mediaViewingHistory.unitId,
          ],
          set: {
            title: parsed.data.title,
            imageUrl: parsed.data.imageUrl ?? null,
            unitTitle: parsed.data.unitTitle ?? null,
            seasonNumber: parsed.data.seasonNumber ?? null,
            episodeNumber: parsed.data.episodeNumber ?? null,
            positionSeconds: sql`greatest(${mediaViewingHistory.positionSeconds}, excluded.position_seconds)`,
            durationSeconds: sql`greatest(${mediaViewingHistory.durationSeconds}, excluded.duration_seconds)`,
            percentage: sql`greatest(${mediaViewingHistory.percentage}, excluded.percentage)`,
            completed: sql`${mediaViewingHistory.completed} OR excluded.completed`,
            visitCount,
            lastViewedAt: now,
            updatedAt: now,
          },
        })
        .returning();

      return { progress: progress ?? null, history: history ?? null };
    });

    return { data: result };
  });
}

async function loadMediaSnapshot(userId: string) {
  const [bookmarks, progress, history] = await Promise.all([
    db
      .select()
      .from(mediaBookmarks)
      .where(eq(mediaBookmarks.userId, userId))
      .orderBy(desc(mediaBookmarks.updatedAt)),
    db
      .select()
      .from(mediaPlaybackProgress)
      .where(eq(mediaPlaybackProgress.userId, userId))
      .orderBy(desc(mediaPlaybackProgress.updatedAt)),
    db
      .select()
      .from(mediaViewingHistory)
      .where(eq(mediaViewingHistory.userId, userId))
      .orderBy(desc(mediaViewingHistory.lastViewedAt)),
  ]);

  return {
    bookmarks,
    progress,
    history: history.slice(0, 100),
    stats: summarizeMediaAccount(bookmarks, progress, history),
  };
}
