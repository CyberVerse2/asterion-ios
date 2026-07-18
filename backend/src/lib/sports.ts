import { z } from "zod";

const STREAMED_ORIGIN = "https://streamed.pk";
const STREAMED_API = `${STREAMED_ORIGIN}/api`;
const MATCH_CACHE_TTL_MS = 60_000;

export class FootballSourceError extends Error {
  readonly statusCode = 502;

  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "FootballSourceError";
  }
}

const UpstreamTeamSchema = z.object({
  name: z.string().min(1),
  badge: z.string().optional().default(""),
});

export const StreamSourceSchema = z.object({
  source: z.string().min(1),
  id: z.string().min(1),
});
export type StreamSource = z.infer<typeof StreamSourceSchema>;

const UpstreamMatchSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  category: z.string().min(1),
  date: z.number(),
  poster: z.string().optional(),
  popular: z.boolean(),
  teams: z
    .object({
      home: UpstreamTeamSchema.optional(),
      away: UpstreamTeamSchema.optional(),
    })
    .nullish(),
  sources: z.array(StreamSourceSchema),
});
type UpstreamMatch = z.infer<typeof UpstreamMatchSchema>;

export const FootballTeamSchema = UpstreamTeamSchema.extend({
  badgeURL: z.string().url().nullable(),
});

export const FootballMatchSchema = UpstreamMatchSchema.extend({
  posterURL: z.string().url().nullable(),
  isLive: z.boolean(),
  teams: z
    .object({
      home: FootballTeamSchema.optional(),
      away: FootballTeamSchema.optional(),
    })
    .nullable(),
});
export type FootballMatch = z.infer<typeof FootballMatchSchema>;

export const StreamEntrySchema = z.object({
  id: z.string().min(1),
  streamNo: z.number(),
  language: z.string(),
  hd: z.boolean(),
  embedUrl: z.string().url(),
  source: z.string().min(1),
  viewers: z.number().optional(),
});
export type StreamEntry = z.infer<typeof StreamEntrySchema>;

export const StreamResultSchema = z.object({
  success: z.literal(true),
  data: z.object({
    streams: z.array(StreamEntrySchema),
    matchId: z.string(),
    homeTeam: z.string(),
    awayTeam: z.string(),
  }),
});
export type StreamResult = z.infer<typeof StreamResultSchema>;

const matchCache = new Map<string, { data: UpstreamMatch[]; fetchedAt: number }>();

async function fetchMatchFeed(path: string): Promise<UpstreamMatch[]> {
  const cached = matchCache.get(path);
  if (cached && Date.now() - cached.fetchedAt < MATCH_CACHE_TTL_MS) {
    return cached.data;
  }

  try {
    const response = await fetch(`${STREAMED_API}${path}`);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const matches = z.array(UpstreamMatchSchema).parse(await response.json());
    matchCache.set(path, { data: matches, fetchedAt: Date.now() });
    return matches;
  } catch (error) {
    throw new FootballSourceError(`The football source failed for ${path}.`, {
      cause: error,
    });
  }
}

function badgeURL(code: string): string | null {
  return code ? `${STREAMED_API}/images/badge/${encodeURIComponent(code)}.webp` : null;
}

function posterURL(path?: string): string | null {
  if (!path) return null;
  if (path.startsWith("http://") || path.startsWith("https://")) return path;
  return new URL(path, STREAMED_ORIGIN).toString();
}

function normalizeMatch(match: UpstreamMatch, liveIds: Set<string>): FootballMatch {
  return FootballMatchSchema.parse({
    ...match,
    posterURL: posterURL(match.poster),
    isLive: liveIds.has(match.id),
    teams: match.teams
      ? {
          home: match.teams.home
            ? { ...match.teams.home, badgeURL: badgeURL(match.teams.home.badge) }
            : undefined,
          away: match.teams.away
            ? { ...match.teams.away, badgeURL: badgeURL(match.teams.away.badge) }
            : undefined,
        }
      : null,
  });
}

async function getRawLiveFootballMatches(): Promise<UpstreamMatch[]> {
  const matches = await fetchMatchFeed("/matches/live");
  return matches.filter((match) => match.category.toLowerCase() === "football");
}

function normalizeAndSort(matches: UpstreamMatch[], liveMatches: UpstreamMatch[]): FootballMatch[] {
  const liveIds = new Set(liveMatches.map((match) => match.id));
  return matches.map((match) => normalizeMatch(match, liveIds)).sort((a, b) => a.date - b.date);
}

export async function getFootballMatches(): Promise<FootballMatch[]> {
  const [matches, liveMatches] = await Promise.all([
    fetchMatchFeed("/matches/football"),
    getRawLiveFootballMatches(),
  ]);
  return normalizeAndSort(matches, liveMatches);
}

export async function getLiveFootballMatches(): Promise<FootballMatch[]> {
  const liveMatches = await getRawLiveFootballMatches();
  return normalizeAndSort(liveMatches, liveMatches);
}

export async function getPopularFootballMatches(): Promise<FootballMatch[]> {
  const [matches, liveMatches] = await Promise.all([
    fetchMatchFeed("/matches/football/popular"),
    getRawLiveFootballMatches(),
  ]);
  return normalizeAndSort(matches, liveMatches);
}

async function fetchStreams(source: StreamSource): Promise<StreamEntry[]> {
  const response = await fetch(
    `${STREAMED_API}/stream/${encodeURIComponent(source.source)}/${encodeURIComponent(source.id)}`
  );
  if (!response.ok) {
    throw new Error(`${source.source} returned HTTP ${response.status}`);
  }
  return z.array(StreamEntrySchema).parse(await response.json());
}

export async function resolveFootballStreams(
  matchId: string,
  sources: StreamSource[],
  homeTeam: string,
  awayTeam: string
): Promise<StreamResult> {
  if (sources.length === 0) {
    throw new FootballSourceError("This match has no stream providers.");
  }

  const results = await Promise.allSettled(sources.map(fetchStreams));
  const streams = results.flatMap((result) => (result.status === "fulfilled" ? result.value : []));

  if (streams.length === 0) {
    const firstFailure = results.find(
      (result): result is PromiseRejectedResult => result.status === "rejected"
    );
    throw new FootballSourceError("No stream provider responded for this match.", {
      cause: firstFailure?.reason,
    });
  }

  const uniqueStreams = Array.from(
    new Map(streams.map((stream) => [`${stream.embedUrl}:${stream.streamNo}`, stream])).values()
  );

  return StreamResultSchema.parse({
    success: true,
    data: {
      streams: uniqueStreams,
      matchId,
      homeTeam,
      awayTeam,
    },
  });
}
