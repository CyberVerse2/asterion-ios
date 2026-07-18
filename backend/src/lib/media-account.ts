export type AccountMediaType = "anime" | "movie" | "football";

export interface MediaBookmarkForStats {
  mediaType: string;
}

export interface MediaProgressForStats {
  mediaType: string;
  completed: boolean;
}

export interface MediaHistoryForStats {
  mediaType: string;
  completed: boolean;
  positionSeconds: number;
  durationSeconds: number;
}

export interface MediaAccountStats {
  savedAnime: number;
  savedMovies: number;
  savedMatches: number;
  animeEpisodesCompleted: number;
  movieUnitsCompleted: number;
  titlesInProgress: number;
  trackedWatchSeconds: number;
  recentActivity: number;
}

export function summarizeMediaAccount(
  bookmarks: readonly MediaBookmarkForStats[],
  progress: readonly MediaProgressForStats[],
  history: readonly MediaHistoryForStats[]
): MediaAccountStats {
  const trackedWatchSeconds = history.reduce((total, entry) => {
    const position = Number.isFinite(entry.positionSeconds)
      ? Math.max(0, entry.positionSeconds)
      : 0;
    const duration = Number.isFinite(entry.durationSeconds)
      ? Math.max(0, entry.durationSeconds)
      : 0;
    return total + (duration > 0 ? Math.min(position, duration) : position);
  }, 0);

  return {
    savedAnime: bookmarks.filter((entry) => entry.mediaType === "anime").length,
    savedMovies: bookmarks.filter((entry) => entry.mediaType === "movie").length,
    savedMatches: bookmarks.filter((entry) => entry.mediaType === "football").length,
    animeEpisodesCompleted: history.filter(
      (entry) => entry.mediaType === "anime" && entry.completed
    ).length,
    movieUnitsCompleted: history.filter(
      (entry) => entry.mediaType === "movie" && entry.completed
    ).length,
    titlesInProgress: progress.filter((entry) => !entry.completed).length,
    trackedWatchSeconds: Math.round(trackedWatchSeconds),
    recentActivity: history.length,
  };
}
