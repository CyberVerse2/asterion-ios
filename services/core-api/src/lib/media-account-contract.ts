import { z } from "zod";

const mediaTypeSchema = z.enum(["anime", "movie", "football"]);
const playbackMediaTypeSchema = z.enum(["anime", "movie"]);
const postgresIntegerMax = 2_147_483_647;
const maximumPlaybackSeconds = 7 * 24 * 60 * 60;
const secureImageURLSchema = z.string().trim().max(2_048).url().refine((value) => {
  const url = new URL(value);
  return url.protocol === "https:" && url.username === "" && url.password === "";
}, "Image URL must be a credential-free HTTPS URL.");
const clientEventDateSchema = z.coerce.date().refine((value) => {
  const earliest = Date.UTC(2000, 0, 1);
  const latest = Date.now() + 5 * 60 * 1_000;
  return value.getTime() >= earliest && value.getTime() <= latest;
}, "Client event time is outside the accepted range.");

export const mediaBookmarkSchema = z.object({
  mediaType: mediaTypeSchema,
  contentId: z.string().trim().min(1).max(500),
  title: z.string().trim().min(1).max(500),
  subtitle: z.string().trim().max(500).nullable().optional(),
  imageUrl: secureImageURLSchema.nullable().optional(),
  clientEventAt: clientEventDateSchema,
}).strict();

export const mediaBookmarkDeleteSchema = mediaBookmarkSchema;

export const mediaProgressSchema = z.object({
  mediaType: playbackMediaTypeSchema,
  contentId: z.string().trim().min(1).max(500),
  title: z.string().trim().min(1).max(500),
  imageUrl: secureImageURLSchema.nullable().optional(),
  unitId: z.string().trim().min(1).max(500),
  unitTitle: z.string().trim().max(500).nullable().optional(),
  seasonNumber: z.number().int().min(0).max(postgresIntegerMax).nullable().optional(),
  episodeNumber: z.number().int().min(0).max(postgresIntegerMax).nullable().optional(),
  positionSeconds: z.number().finite().min(0).max(maximumPlaybackSeconds),
  durationSeconds: z.number().finite().min(0).max(maximumPlaybackSeconds),
  completed: z.boolean().optional(),
  started: z.boolean().optional().default(false),
  sessionId: z.string().uuid(),
  clientEventAt: clientEventDateSchema,
}).strict();

interface BookmarkStatsRow {
  savedAnime?: unknown;
  savedMovies?: unknown;
  savedMatches?: unknown;
}

interface ProgressStatsRow {
  titlesInProgress?: unknown;
}

interface HistoryStatsRow {
  animeEpisodesCompleted?: unknown;
  movieUnitsCompleted?: unknown;
  historyEntries?: unknown;
  activityLast30Days?: unknown;
}

export function formatMediaAccountStats(
  bookmark: BookmarkStatsRow | undefined,
  progress: ProgressStatsRow | undefined,
  history: HistoryStatsRow | undefined
) {
  return {
    savedAnime: countValue(bookmark?.savedAnime),
    savedMovies: countValue(bookmark?.savedMovies),
    savedMatches: countValue(bookmark?.savedMatches),
    animeEpisodesCompleted: countValue(history?.animeEpisodesCompleted),
    movieUnitsCompleted: countValue(history?.movieUnitsCompleted),
    titlesInProgress: countValue(progress?.titlesInProgress),
    historyEntries: countValue(history?.historyEntries),
    activityLast30Days: countValue(history?.activityLast30Days),
  };
}

function countValue(value: unknown): number {
  const count = Number(value ?? 0);
  return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}
