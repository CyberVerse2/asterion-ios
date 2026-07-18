import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { and, desc, eq, sql } from "drizzle-orm";
import {
  mediaBookmarks,
  mediaPlaybackProgress,
  mediaViewingHistory,
} from "../db/schema";
import { db } from "../lib/db";
import {
  formatMediaAccountStats,
  mediaBookmarkDeleteSchema,
  mediaBookmarkSchema,
  mediaProgressSchema,
} from "../lib/media-account-contract";
import {
  buildMediaBookmarkUpsert,
  buildMediaHistoryUpsert,
  buildMediaProgressUpsert,
  buildMediaSessionInsert,
} from "../lib/media-account-queries";
import { ensureUser } from "../lib/users";

export function registerMediaAccountRoutes(app: FastifyInstance) {
  app.get("/me/media", async (request) => {
    const { user } = await ensureUser(request.auth.clerkUserId);
    const snapshot = await loadMediaSnapshot(user.id);
    return { data: snapshot };
  });

  app.put("/me/media/bookmarks", async (request, reply) => {
    const parsed = mediaBookmarkSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid media bookmark payload.",
        issues: parsed.error.flatten(),
      });
    }

    const { user } = await ensureUser(request.auth.clerkUserId);
    const [state] = await buildMediaBookmarkUpsert(
      db,
      {
        id: randomUUID(),
        userId: user.id,
        mediaType: parsed.data.mediaType,
        contentId: parsed.data.contentId,
        title: parsed.data.title,
        subtitle: parsed.data.subtitle ?? null,
        imageUrl: parsed.data.imageUrl ?? null,
        isSaved: true,
        clientUpdatedAt: parsed.data.clientEventAt,
      },
      new Date()
    );

    return { data: bookmarkMutationResult(state) };
  });

  app.delete("/me/media/bookmarks", async (request, reply) => {
    const parsed = mediaBookmarkDeleteSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid media bookmark identifier." });
    }

    const { user } = await ensureUser(request.auth.clerkUserId);
    const [state] = await buildMediaBookmarkUpsert(
      db,
      {
        id: randomUUID(),
        userId: user.id,
        mediaType: parsed.data.mediaType,
        contentId: parsed.data.contentId,
        title: parsed.data.title,
        subtitle: parsed.data.subtitle ?? null,
        imageUrl: parsed.data.imageUrl ?? null,
        isSaved: false,
        clientUpdatedAt: parsed.data.clientEventAt,
      },
      new Date()
    );

    return { data: bookmarkMutationResult(state) };
  });

  app.put("/me/media/progress", async (request, reply) => {
    const parsed = mediaProgressSchema.safeParse(request.body);
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
    const unitId = parsed.data.unitId;
    const now = new Date();
    const clientEventAt = parsed.data.clientEventAt;

    const result = await db.transaction(async (tx) => {
      const [progress] = await buildMediaProgressUpsert(
        tx,
        {
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
          clientUpdatedAt: clientEventAt,
        },
        now
      );

      const insertedSessions = parsed.data.started
        ? await buildMediaSessionInsert(
            tx,
            {
              id: randomUUID(),
              userId: user.id,
              sessionId: parsed.data.sessionId,
              mediaType: parsed.data.mediaType,
              contentId: parsed.data.contentId,
              unitId,
              clientStartedAt: clientEventAt,
            }
          )
        : [];
      const incrementsVisitCount = insertedSessions.length > 0;
      const [history] = await buildMediaHistoryUpsert(
        tx,
        {
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
          visitCount: incrementsVisitCount ? 1 : 0,
          firstViewedAt: clientEventAt,
          lastViewedAt: clientEventAt,
          clientUpdatedAt: clientEventAt,
        },
        now,
        incrementsVisitCount
      );

      return { progress: progress ?? null, history: history ?? null };
    });

    return { data: result };
  });
}

async function loadMediaSnapshot(userId: string) {
  const [bookmarks, progress, history, stats] = await Promise.all([
    db
      .select()
      .from(mediaBookmarks)
      .where(and(
        eq(mediaBookmarks.userId, userId),
        eq(mediaBookmarks.isSaved, true)
      ))
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
      .orderBy(desc(mediaViewingHistory.lastViewedAt), desc(mediaViewingHistory.id))
      .limit(100),
    loadMediaStats(userId),
  ]);

  return {
    bookmarks,
    progress,
    history,
    stats,
  };
}

async function loadMediaStats(userId: string) {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1_000);
  const [bookmarkStats, progressStats, historyStats] = await Promise.all([
    db
      .select({
        savedAnime: sql<number>`count(*) filter (where ${mediaBookmarks.mediaType} = 'anime' and ${mediaBookmarks.isSaved} = true)::int`,
        savedMovies: sql<number>`count(*) filter (where ${mediaBookmarks.mediaType} = 'movie' and ${mediaBookmarks.isSaved} = true)::int`,
        savedMatches: sql<number>`count(*) filter (where ${mediaBookmarks.mediaType} = 'football' and ${mediaBookmarks.isSaved} = true)::int`,
      })
      .from(mediaBookmarks)
      .where(eq(mediaBookmarks.userId, userId)),
    db
      .select({
        titlesInProgress: sql<number>`count(*) filter (where ${mediaPlaybackProgress.completed} = false)::int`,
      })
      .from(mediaPlaybackProgress)
      .where(eq(mediaPlaybackProgress.userId, userId)),
    db
      .select({
        animeEpisodesCompleted: sql<number>`count(*) filter (where ${mediaViewingHistory.mediaType} = 'anime' and ${mediaViewingHistory.completed} = true)::int`,
        movieUnitsCompleted: sql<number>`count(*) filter (where ${mediaViewingHistory.mediaType} = 'movie' and ${mediaViewingHistory.completed} = true)::int`,
        historyEntries: sql<number>`count(*)::int`,
        activityLast30Days: sql<number>`count(*) filter (where ${mediaViewingHistory.lastViewedAt} >= ${thirtyDaysAgo})::int`,
      })
      .from(mediaViewingHistory)
      .where(eq(mediaViewingHistory.userId, userId)),
  ]);

  return formatMediaAccountStats(bookmarkStats[0], progressStats[0], historyStats[0]);
}

function bookmarkMutationResult(state: typeof mediaBookmarks.$inferSelect | undefined) {
  if (!state) return null;
  return {
    bookmark: state.isSaved ? state : null,
    isSaved: state.isSaved,
    clientUpdatedAt: state.clientUpdatedAt,
  };
}
