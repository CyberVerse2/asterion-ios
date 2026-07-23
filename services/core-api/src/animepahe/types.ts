// ─── AnimePahe API Types ────────────────────────────────────────────
// Reverse-engineered from animepahe.pw / animepahe.com
// API is JSON-based with ?m= parameter routing. Responses are wrapped
// in arrays with metadata.

export interface AnimeSearchResult {
  id: number;
  title: string;
  type: string;              // "TV", "Movie", "OVA", "ONA", "Special"
  episodes: number;
  season: string;            // e.g. "Winter 2024"
  year: number;
  score: number;             // 0-10
  poster: string;            // relative URL like "/posters/abc.jpg"
  session: string;           // session_id for subsequent API calls
  status: string;            // "Completed", "Airing"
}

export interface AnimeSearchResponse {
  total: number;
  per_page: number;
  current_page: number;
  last_page: number;
  from: number;
  to: number;
  data: AnimeSearchResult[];
}

export interface AnimeDetailResult {
  id: number;
  title: string;
  title_english: string;
  title_japanese: string;
  type: string;
  episodes: number;
  status: string;
  aired: string;
  premiered: string;
  producers: string[];
  studios: string[];
  source: string;
  genres: string[];
  duration: string;
  rating: string;
  score: number;
  scored_by: number;
  rank: number;
  popularity: number;
  members: number;
  favorites: number;
  synopsis: string;
  background: string;
  poster: string;
  session: string;
  mal_id?: number;
  season?: string;
  year?: number;
  trailer?: { id: string; site: string; thumbnail: string } | null;
}

export interface AnimeDetailResponse {
  data: AnimeDetailResult;
}

export interface AnimeEpisode {
  id: number;
  anime_id: number;
  episode: number;
  snapshot: string;
  session: string;
  created_at: string;
  disc?: string;
  duration?: string;
  aired?: string;
  fansub?: string;
  audio?: string;
}

export interface EpisodeListResponse {
  total: number;
  per_page: number;
  current_page: number;
  last_page: number;
  from: number;
  to: number;
  data: AnimeEpisode[];
}

export interface PahewinVideoSource {
  id: number;
  session: string;
  episode_id: number;
  quality: string;           // "360p", "720p", "1080p"
  audio: string;             // "eng", "jpn"
  source: string;            // "kwik", "mp4upload", "streamsb"
  url: string;               // direct or redirect URL
  size: number;              // bytes
  type: string;              // "mp4"
}

export interface PahewinEpisodeData {
  id: number;
  episode: number;
  snapshot: string;
  disc: string;
  duration: string;
  session: string;
  created_at: string;
  fansub: string;
  audio: string;
  video: PahewinVideoSource[];
}

export interface PahewinAnimeResponse {
  data: PahewinEpisodeData[];
}

// ─── Feed / Recent ──────────────────────────────────────────────────

export interface FeedItem {
  id: number;
  title: string;
  episode: number;
  type: string;
  season: string;
  session: string;           // anime session
  episode_session: string;   // episode session
  snapshot: string;
  created_at: string;
  fansub: string;
  audio: string;
  duration: string;
  score: number;
}

export interface FeedResponse {
  total: number;
  per_page: number;
  current_page: number;
  last_page: number;
  data: FeedItem[];
}

// ─── Genre List ─────────────────────────────────────────────────────

export interface GenreItem {
  id: number;
  name: string;
  count: number;
}

export interface GenreListResponse {
  data: GenreItem[];
}

// ─── Airing Schedule ────────────────────────────────────────────────

export interface AiringItem {
  id: number;
  title: string;
  poster: string;
  session: string;
  episode: number;
  score: number;
  type: string;
  aired: string;
}

export interface AiringResponse {
  data: AiringItem[];
}

// ─── Kwik Video Extraction ──────────────────────────────────────────
// Kwik.si is the primary video host. Its extraction requires:
// 1. Load kwik page (POST, form data: kwik=aes_encrypted_token)
// 2. Parse the HTML for the M3U8 / redirect URL
// 3. The token is a URL segment after /f/ or /d/

export interface KwikExtractionResult {
  m3u8?: string;
  mp4?: string;
  subtitles?: string;
  error?: string;
}
