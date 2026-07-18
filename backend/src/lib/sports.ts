import { z } from "zod";

const STREAMED_API = "https://streamed.pk/api";

// ── Types ───────────────────────────────────────────────────────────────────

export const SportSchema = z.object({
  id: z.string(),
  name: z.string(),
});
export type Sport = z.infer<typeof SportSchema>;

export const TeamSchema = z.object({
  name: z.string(),
  badge: z.string(),
});
export type Team = z.infer<typeof TeamSchema>;

export const StreamSourceSchema = z.object({
  source: z.enum(["admin", "delta", "echo"]),
  id: z.string(),
});
export type StreamSource = z.infer<typeof StreamSourceSchema>;

export const MatchSchema = z.object({
  id: z.string(),
  title: z.string(),
  category: z.string(),
  date: z.number(),
  poster: z.string().optional(),
  popular: z.boolean(),
  isLive: z.boolean(),
  teams: z.object({
    home: TeamSchema,
    away: TeamSchema,
  }),
  sources: z.array(StreamSourceSchema),
});
export type Match = z.infer<typeof MatchSchema>;

export const StreamEntrySchema = z.object({
  id: z.string(),
  streamNo: z.number(),
  language: z.string(),
  hd: z.boolean(),
  embedUrl: z.string(),
  source: z.string(),
  viewers: z.number(),
});
export type StreamEntry = z.infer<typeof StreamEntrySchema>;

export const StreamResultSchema = z.object({
  success: z.boolean(),
  data: z
    .object({
      streams: z.array(StreamEntrySchema),
      matchId: z.string(),
      homeTeam: z.string(),
      awayTeam: z.string(),
    })
    .optional(),
  error: z.string().optional(),
});
export type StreamResult = z.infer<typeof StreamResultSchema>;

// ── Cached sports ───────────────────────────────────────────────────────────

let cachedSports: Sport[] | null = null;
let sportsCacheTime = 0;
const SPORTS_CACHE_TTL = 300_000; // 5 minutes

export async function getSports(): Promise<Sport[]> {
  if (cachedSports && Date.now() - sportsCacheTime < SPORTS_CACHE_TTL) {
    return cachedSports;
  }

  try {
    const res = await fetch(`${STREAMED_API}/sports`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json() as Sport[];
    cachedSports = data;
    sportsCacheTime = Date.now();
    return data;
  } catch {
    if (cachedSports) return cachedSports;
    // fallback static list
    return [
      { id: "football", name: "Football" },
      { id: "basketball", name: "Basketball" },
      { id: "american-football", name: "American Football" },
      { id: "hockey", name: "Hockey" },
      { id: "baseball", name: "Baseball" },
      { id: "motor-sports", name: "Motor Sports" },
      { id: "fight", name: "Fight (UFC, Boxing)" },
      { id: "tennis", name: "Tennis" },
      { id: "rugby", name: "Rugby" },
      { id: "golf", name: "Golf" },
      { id: "billiards", name: "Billiards" },
      { id: "afl", name: "AFL" },
      { id: "darts", name: "Darts" },
      { id: "cricket", name: "Cricket" },
      { id: "other", name: "Other" },
    ];
  }
}

// ── Matches (live from streamed.pk) ─────────────────────────────────────────

const matchCache = new Map<string, { data: Match[]; time: number }>();
const MATCH_CACHE_TTL = 60_000; // 1 minute

const MATCH_DURATION_MS = 2.5 * 60 * 60 * 1000; // 2.5 hours typical match window

function computeLiveStatus(dateMs: number): boolean {
  const now = Date.now();
  return now >= dateMs && now <= dateMs + MATCH_DURATION_MS;
}

function enrichMatch(m: Record<string, unknown>): Match {
  const dateMs = (m.date as number) ?? 0;
  return {
    ...m,
    isLive: computeLiveStatus(dateMs),
  } as Match;
}

export async function getMatchesBySport(sportId: string): Promise<Match[]> {
  const cached = matchCache.get(sportId);
  if (cached && Date.now() - cached.time < MATCH_CACHE_TTL) {
    return cached.data;
  }

  try {
    const res = await fetch(`${STREAMED_API}/matches/${sportId}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (!Array.isArray(data)) throw new Error("Invalid response");

    const matches = data.map((m: Record<string, unknown>) => enrichMatch(m));

    matchCache.set(sportId, { data: matches, time: Date.now() });
    return matches;
  } catch {
    if (cached) return cached.data;
    return [];
  }
}

export async function getLiveMatches(): Promise<Match[]> {
  const sports = await getSports();
  const allLive: Match[] = [];

  for (const sport of sports) {
    const matches = await getMatchesBySport(sport.id);
    allLive.push(...matches.filter((m) => m.isLive));
  }

  return allLive.sort((a, b) => a.date - b.date);
}

// ── In-memory seed store (for POST /api/matches fallback) ────────────────────

export const matchStore: Match[] = [];

export function addMatch(match: Match) {
  const idx = matchStore.findIndex((m) => m.id === match.id);
  if (idx >= 0) {
    matchStore[idx] = match;
  } else {
    matchStore.push(match);
  }
}

export function getMatchById(matchId: string): Match | undefined {
  return matchStore.find((m) => m.id === matchId);
}

// ── Stream Resolution (direct from streamed.pk) ──────────────────────────────

export async function resolveStreams(
  matchId: string,
  sources: StreamSource[],
  homeTeam: string,
  awayTeam: string
): Promise<StreamResult> {
  const allStreams: StreamEntry[] = [];

  for (const src of sources) {
    try {
      const res = await fetch(`${STREAMED_API}/stream/${src.source}/${src.id}`);
      if (!res.ok) continue;
      const data = await res.json();
      if (Array.isArray(data)) {
        allStreams.push(...(data as StreamEntry[]));
      }
    } catch {
      // skip unavailable sources
    }
  }

  if (!allStreams.length) {
    return {
      success: false,
      error: "No stream sources available for this match.",
    };
  }

  return {
    success: true,
    data: {
      streams: allStreams,
      matchId,
      homeTeam,
      awayTeam,
    },
  };
}

// ── Image helpers ────────────────────────────────────────────────────────────

export function badgeUrl(badgeCode: string): string {
  if (!badgeCode) return "";
  return `${STREAMED_API}/images/badge/${badgeCode}.webp`;
}

export function posterUrl(posterPath: string): string {
  if (!posterPath) return "";
  if (posterPath.startsWith("http")) return posterPath;
  return `https://streamed.pk${posterPath}`;
}
