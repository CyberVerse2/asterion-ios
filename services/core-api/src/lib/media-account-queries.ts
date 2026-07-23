import { sql } from "drizzle-orm";
import type { db } from "./db";
import {
  mediaBookmarks,
  mediaPlaybackProgress,
  mediaPlaybackSessions,
  mediaViewingHistory,
} from "../db/schema";

type InsertExecutor = Pick<typeof db, "insert">;
type BookmarkInsert = typeof mediaBookmarks.$inferInsert;
type ProgressInsert = typeof mediaPlaybackProgress.$inferInsert;
type SessionInsert = typeof mediaPlaybackSessions.$inferInsert;
type HistoryInsert = typeof mediaViewingHistory.$inferInsert;

export function buildMediaBookmarkUpsert(
  executor: InsertExecutor,
  values: BookmarkInsert,
  serverUpdatedAt: Date
) {
  return executor
    .insert(mediaBookmarks)
    .values(values)
    .onConflictDoUpdate({
      target: [mediaBookmarks.userId, mediaBookmarks.mediaType, mediaBookmarks.contentId],
      set: {
        title: sql`CASE WHEN excluded.client_updated_at >= ${mediaBookmarks.clientUpdatedAt} THEN excluded.title ELSE ${mediaBookmarks.title} END`,
        subtitle: sql`CASE WHEN excluded.client_updated_at >= ${mediaBookmarks.clientUpdatedAt} THEN excluded.subtitle ELSE ${mediaBookmarks.subtitle} END`,
        imageUrl: sql`CASE WHEN excluded.client_updated_at >= ${mediaBookmarks.clientUpdatedAt} THEN excluded.image_url ELSE ${mediaBookmarks.imageUrl} END`,
        isSaved: sql`CASE WHEN excluded.client_updated_at >= ${mediaBookmarks.clientUpdatedAt} THEN excluded.is_saved ELSE ${mediaBookmarks.isSaved} END`,
        clientUpdatedAt: sql`greatest(${mediaBookmarks.clientUpdatedAt}, excluded.client_updated_at)`,
        updatedAt: sql`CASE WHEN excluded.client_updated_at >= ${mediaBookmarks.clientUpdatedAt} THEN ${serverUpdatedAt} ELSE ${mediaBookmarks.updatedAt} END`,
      },
    })
    .returning();
}

export function buildMediaProgressUpsert(
  executor: InsertExecutor,
  values: ProgressInsert,
  serverUpdatedAt: Date
) {
  return executor
    .insert(mediaPlaybackProgress)
    .values(values)
    .onConflictDoUpdate({
      target: [
        mediaPlaybackProgress.userId,
        mediaPlaybackProgress.mediaType,
        mediaPlaybackProgress.contentId,
      ],
      set: {
        title: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.title ELSE ${mediaPlaybackProgress.title} END`,
        imageUrl: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.image_url ELSE ${mediaPlaybackProgress.imageUrl} END`,
        unitId: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.unit_id ELSE ${mediaPlaybackProgress.unitId} END`,
        unitTitle: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.unit_title ELSE ${mediaPlaybackProgress.unitTitle} END`,
        seasonNumber: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.season_number ELSE ${mediaPlaybackProgress.seasonNumber} END`,
        episodeNumber: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.episode_number ELSE ${mediaPlaybackProgress.episodeNumber} END`,
        positionSeconds: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.position_seconds ELSE ${mediaPlaybackProgress.positionSeconds} END`,
        durationSeconds: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.duration_seconds ELSE ${mediaPlaybackProgress.durationSeconds} END`,
        percentage: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.percentage ELSE ${mediaPlaybackProgress.percentage} END`,
        completed: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN excluded.completed ELSE ${mediaPlaybackProgress.completed} END`,
        clientUpdatedAt: sql`greatest(${mediaPlaybackProgress.clientUpdatedAt}, excluded.client_updated_at)`,
        updatedAt: sql`CASE WHEN excluded.client_updated_at >= ${mediaPlaybackProgress.clientUpdatedAt} THEN ${serverUpdatedAt} ELSE ${mediaPlaybackProgress.updatedAt} END`,
      },
    })
    .returning();
}

export function buildMediaSessionInsert(
  executor: InsertExecutor,
  values: SessionInsert
) {
  return executor
    .insert(mediaPlaybackSessions)
    .values(values)
    .onConflictDoNothing({
      target: [mediaPlaybackSessions.userId, mediaPlaybackSessions.sessionId],
    })
    .returning({ id: mediaPlaybackSessions.id });
}

export function buildMediaHistoryUpsert(
  executor: InsertExecutor,
  values: HistoryInsert,
  serverUpdatedAt: Date,
  incrementsVisitCount: boolean
) {
  const visitCount = incrementsVisitCount
    ? sql`${mediaViewingHistory.visitCount} + 1`
    : mediaViewingHistory.visitCount;

  return executor
    .insert(mediaViewingHistory)
    .values(values)
    .onConflictDoUpdate({
      target: [
        mediaViewingHistory.userId,
        mediaViewingHistory.mediaType,
        mediaViewingHistory.contentId,
        mediaViewingHistory.unitId,
      ],
      set: {
        title: sql`CASE WHEN excluded.client_updated_at >= ${mediaViewingHistory.clientUpdatedAt} THEN excluded.title ELSE ${mediaViewingHistory.title} END`,
        imageUrl: sql`CASE WHEN excluded.client_updated_at >= ${mediaViewingHistory.clientUpdatedAt} THEN excluded.image_url ELSE ${mediaViewingHistory.imageUrl} END`,
        unitTitle: sql`CASE WHEN excluded.client_updated_at >= ${mediaViewingHistory.clientUpdatedAt} THEN excluded.unit_title ELSE ${mediaViewingHistory.unitTitle} END`,
        seasonNumber: sql`CASE WHEN excluded.client_updated_at >= ${mediaViewingHistory.clientUpdatedAt} THEN excluded.season_number ELSE ${mediaViewingHistory.seasonNumber} END`,
        episodeNumber: sql`CASE WHEN excluded.client_updated_at >= ${mediaViewingHistory.clientUpdatedAt} THEN excluded.episode_number ELSE ${mediaViewingHistory.episodeNumber} END`,
        positionSeconds: sql`greatest(${mediaViewingHistory.positionSeconds}, excluded.position_seconds)`,
        durationSeconds: sql`greatest(${mediaViewingHistory.durationSeconds}, excluded.duration_seconds)`,
        percentage: sql`greatest(${mediaViewingHistory.percentage}, excluded.percentage)`,
        completed: sql`${mediaViewingHistory.completed} OR excluded.completed`,
        visitCount,
        firstViewedAt: sql`least(${mediaViewingHistory.firstViewedAt}, excluded.first_viewed_at)`,
        lastViewedAt: sql`greatest(${mediaViewingHistory.lastViewedAt}, excluded.last_viewed_at)`,
        clientUpdatedAt: sql`greatest(${mediaViewingHistory.clientUpdatedAt}, excluded.client_updated_at)`,
        updatedAt: serverUpdatedAt,
      },
    })
    .returning();
}
