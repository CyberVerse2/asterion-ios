import assert from "node:assert/strict";
import test from "node:test";
import { summarizeMediaAccount } from "../src/lib/media-account";

test("media account stats separate saved types and completed playback", () => {
  const stats = summarizeMediaAccount(
    [
      { mediaType: "anime" },
      { mediaType: "anime" },
      { mediaType: "movie" },
      { mediaType: "football" },
    ],
    [
      { mediaType: "anime", completed: false },
      { mediaType: "movie", completed: true },
    ],
    [
      {
        mediaType: "anime",
        completed: true,
        positionSeconds: 1_200,
        durationSeconds: 1_400,
      },
      {
        mediaType: "movie",
        completed: true,
        positionSeconds: 8_000,
        durationSeconds: 7_200,
      },
      {
        mediaType: "anime",
        completed: false,
        positionSeconds: Number.NaN,
        durationSeconds: 1_400,
      },
    ]
  );

  assert.deepEqual(stats, {
    savedAnime: 2,
    savedMovies: 1,
    savedMatches: 1,
    animeEpisodesCompleted: 1,
    movieUnitsCompleted: 1,
    titlesInProgress: 1,
    trackedWatchSeconds: 8_400,
    recentActivity: 3,
  });
});
