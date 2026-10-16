export interface MissingPlan {
  /** Every chapter number in 1..latest that is not stored (holes plus new tail). */
  missing: number[];
  /** Missing numbers skipped this run because a recent miss is still backing off. */
  deferred: number[];
  /** What this run will fetch: new tail chapters first, then holes, capped at `max`. */
  toFetch: number[];
  holes: number;
  tail: number;
}

/**
 * Works out which chapters a novel still needs.
 *
 * Unlike the old scraper (which resumed from MAX(chapter_number) + 1 and so never revisited a
 * hole), this compares the full 1..latest range against what is stored.
 */
export function planMissingChapters(
  stored: Iterable<number>,
  latest: number,
  options: { deferred?: Iterable<number>; max?: number } = {}
): MissingPlan {
  const have = new Set<number>();
  let maxStored = 0;
  for (const number of stored) {
    if (!Number.isSafeInteger(number) || number < 1) continue;
    have.add(number);
    if (number > maxStored) maxStored = number;
  }
  const backingOff = new Set(options.deferred ?? []);

  const missing: number[] = [];
  const deferred: number[] = [];
  const tailNumbers: number[] = [];
  const holeNumbers: number[] = [];

  const upper = Number.isSafeInteger(latest) && latest > 0 ? latest : 0;
  for (let number = 1; number <= upper; number++) {
    if (have.has(number)) continue;
    missing.push(number);
    if (backingOff.has(number)) {
      deferred.push(number);
    } else if (number > maxStored) {
      tailNumbers.push(number);
    } else {
      holeNumbers.push(number);
    }
  }

  const ordered = [...tailNumbers, ...holeNumbers];
  const max = options.max !== undefined && options.max >= 0 ? options.max : ordered.length;
  return {
    missing,
    deferred,
    toFetch: ordered.slice(0, max),
    holes: missing.filter((number) => number <= maxStored).length,
    tail: missing.filter((number) => number > maxStored).length
  };
}

/** Compresses [1,2,3,7,9,10] into "1-3, 7, 9-10" for logs. */
export function formatRanges(numbers: readonly number[], limit = 6): string {
  if (numbers.length === 0) return '-';
  const sorted = [...numbers].sort((a, b) => a - b);
  const ranges: string[] = [];
  let start = sorted[0]!;
  let previous = start;
  for (const number of sorted.slice(1)) {
    if (number === previous + 1) {
      previous = number;
      continue;
    }
    ranges.push(start === previous ? `${start}` : `${start}-${previous}`);
    start = previous = number;
  }
  ranges.push(start === previous ? `${start}` : `${start}-${previous}`);
  return ranges.length > limit
    ? `${ranges.slice(0, limit).join(', ')}, … (+${ranges.length - limit} ranges)`
    : ranges.join(', ');
}

/** Next UTC time at hour:minute strictly after `now`. */
export function nextScheduledRun(now: Date, hourUtc: number, minuteUtc: number): Date {
  const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), hourUtc, minuteUtc, 0, 0));
  if (next.getTime() <= now.getTime()) {
    next.setUTCDate(next.getUTCDate() + 1);
  }
  return next;
}

/** True when the last completed run is missing or older than the interval. */
export function isRunOverdue(lastCompletedAt: Date | null, now: Date, intervalHours: number): boolean {
  if (!lastCompletedAt) return true;
  return now.getTime() - lastCompletedAt.getTime() >= intervalHours * 3600_000;
}
