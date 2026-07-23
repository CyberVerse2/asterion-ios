import assert from "node:assert/strict";
import test from "node:test";
import { drizzle } from "drizzle-orm/node-postgres";
import { getTableConfig } from "drizzle-orm/pg-core";
import {
  mediaPlaybackProgress,
  mediaBookmarks,
  mediaPlaybackSessions,
  mediaViewingHistory,
} from "../src/db/schema";
import {
  formatMediaAccountStats,
  mediaBookmarkDeleteSchema,
  mediaProgressSchema,
} from "../src/lib/media-account-contract";
import {
  buildMediaBookmarkUpsert,
  buildMediaHistoryUpsert,
  buildMediaProgressUpsert,
  buildMediaSessionInsert,
} from "../src/lib/media-account-queries";

test("media account stats format database aggregates for every media type", () => {
  assert.deepEqual(
    formatMediaAccountStats(
      { savedAnime: "2", savedMovies: 1, savedMatches: 3 },
      { titlesInProgress: 4 },
      {
        animeEpisodesCompleted: 8,
        movieUnitsCompleted: "5",
        historyEntries: 21,
        activityLast30Days: 7,
      }
    ),
    {
      savedAnime: 2,
      savedMovies: 1,
      savedMatches: 3,
      animeEpisodesCompleted: 8,
      movieUnitsCompleted: 5,
      titlesInProgress: 4,
      historyEntries: 21,
      activityLast30Days: 7,
    }
  );
});

test("media progress validation bounds database values and requires explicit identity", () => {
  const valid = {
    mediaType: "movie",
    contentId: "film-1",
    title: "Film One",
    imageUrl: "https://images.example/film.jpg",
    unitId: "film-1",
    positionSeconds: 120,
    durationSeconds: 7_200,
    started: true,
    sessionId: "5fbda4c7-d863-4a1f-92bd-a0326f68d460",
    clientEventAt: new Date().toISOString(),
  };

  assert.equal(mediaProgressSchema.safeParse(valid).success, true);
  assert.equal(mediaProgressSchema.safeParse({ ...valid, unitId: undefined }).success, false);
  assert.equal(
    mediaProgressSchema.safeParse({ ...valid, imageUrl: "http://images.example/film.jpg" }).success,
    false
  );
  assert.equal(
    mediaProgressSchema.safeParse({ ...valid, imageUrl: "https://user:secret@images.example/film.jpg" }).success,
    false
  );
  assert.equal(
    mediaProgressSchema.safeParse({ ...valid, episodeNumber: 2_147_483_648 }).success,
    false
  );
  assert.equal(mediaProgressSchema.safeParse({ ...valid, durationSeconds: 604_801 }).success, false);
});

test("account identity comes from authentication and cannot be supplied in requests", () => {
  const spoofed = mediaBookmarkDeleteSchema.safeParse({
    mediaType: "anime",
    contentId: "show-1",
    title: "Show One",
    clientEventAt: new Date().toISOString(),
    userId: "another-user",
  });
  assert.equal(spoofed.success, false);
});

test("database schema requires unit identity and deduplicates playback sessions", () => {
  assert.equal(mediaPlaybackProgress.unitId.notNull, true);
  assert.equal(mediaViewingHistory.unitId.notNull, true);

  const sessionIndex = getTableConfig(mediaPlaybackSessions).indexes.find(
    (index) => index.config.name === "media_session_user_id_unique"
  );
  assert.ok(sessionIndex?.config.unique);
  assert.deepEqual(
    sessionIndex.config.columns.map((column) => "name" in column ? column.name : null),
    ["user_id", "session_id"]
  );
});

test("production upserts preserve newer progress and make session starts retry-safe", () => {
  const database = drizzle.mock();
  const now = new Date("2026-07-18T12:00:00.000Z");
  const base = {
    id: "progress-1",
    userId: "user-1",
    mediaType: "anime",
    contentId: "show-1",
    title: "Show One",
    imageUrl: null,
    unitId: "episode-3",
    unitTitle: "Episode 3",
    seasonNumber: null,
    episodeNumber: 3,
    positionSeconds: 600,
    durationSeconds: 1_200,
    percentage: 50,
    completed: false,
    clientUpdatedAt: new Date("2026-07-18T11:59:00.000Z"),
  };

  const bookmarkSQL = buildMediaBookmarkUpsert(database, {
    id: "bookmark-1",
    userId: "user-1",
    mediaType: "anime",
    contentId: "show-1",
    title: "Show One",
    subtitle: null,
    imageUrl: null,
    isSaved: false,
    clientUpdatedAt: base.clientUpdatedAt,
  }, now).toSQL().sql;
  assert.match(bookmarkSQL, /on conflict \("user_id","media_type","content_id"\) do update/);
  assert.match(bookmarkSQL, /excluded\.client_updated_at >= "media_bookmarks"\."client_updated_at"/);
  assert.equal(mediaBookmarks.clientUpdatedAt.notNull, true);

  const progressSQL = buildMediaProgressUpsert(database, base, now).toSQL().sql;
  assert.match(progressSQL, /on conflict \("user_id","media_type","content_id"\) do update/);
  assert.match(progressSQL, /excluded\.client_updated_at >= "media_playback_progress"\."client_updated_at"/);
  assert.match(progressSQL, /greatest\("media_playback_progress"\."client_updated_at", excluded\.client_updated_at\)/);

  const sessionSQL = buildMediaSessionInsert(database, {
    id: "row-1",
    userId: "user-1",
    sessionId: "5fbda4c7-d863-4a1f-92bd-a0326f68d460",
    mediaType: "anime",
    contentId: "show-1",
    unitId: "episode-3",
    clientStartedAt: base.clientUpdatedAt,
  }).toSQL().sql;
  assert.match(sessionSQL, /on conflict \("user_id","session_id"\) do nothing/);

  const historySQL = buildMediaHistoryUpsert(database, {
    ...base,
    id: "history-1",
    visitCount: 1,
    firstViewedAt: base.clientUpdatedAt,
    lastViewedAt: base.clientUpdatedAt,
  }, now, true).toSQL().sql;
  assert.match(historySQL, /greatest\("media_viewing_history"\."last_viewed_at", excluded\.last_viewed_at\)/);
  assert.match(historySQL, /"media_viewing_history"\."visit_count" \+ 1/);
});
