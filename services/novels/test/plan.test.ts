import assert from 'node:assert/strict';
import test from 'node:test';

import type { NovelRow } from '../src/db.js';
import type { NovelPageMeta } from '../src/parse.js';
import { formatRanges, isRunOverdue, nextScheduledRun, planMissingChapters } from '../src/plan.js';
import { diffNovelMeta, summaryKey } from '../src/runner.js';

const range = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

test('a novel with only its first 10 chapters needs 11..latest', () => {
  const plan = planMissingChapters(range(1, 10), 2456);
  assert.equal(plan.missing.length, 2446);
  assert.equal(plan.tail, 2446);
  assert.equal(plan.holes, 0);
  assert.equal(plan.toFetch[0], 11);
  assert.equal(plan.toFetch.at(-1), 2456);
});

test('holes below the highest stored chapter are found (the old max+1 resume never saw them)', () => {
  const stored = [...range(1, 11), ...range(15, 20), ...range(22, 30)];
  const plan = planMissingChapters(stored, 30);
  assert.deepEqual(plan.missing, [12, 13, 14, 21]);
  assert.equal(plan.holes, 4);
  assert.equal(plan.tail, 0);
});

test('new tail chapters are fetched before holes, and the cap applies to the combined list', () => {
  const stored = [...range(1, 4), ...range(7, 10)];
  const plan = planMissingChapters(stored, 13, { max: 4 });
  assert.deepEqual(plan.missing, [5, 6, 11, 12, 13]);
  assert.deepEqual(plan.toFetch, [11, 12, 13, 5]);
});

test('misses that are still backing off are skipped but still reported as missing', () => {
  const plan = planMissingChapters(range(1, 5), 9, { deferred: [7, 8] });
  assert.deepEqual(plan.missing, [6, 7, 8, 9]);
  assert.deepEqual(plan.deferred, [7, 8]);
  assert.deepEqual(plan.toFetch, [6, 9]);
});

test('an up-to-date novel needs nothing; duplicates and junk numbers are ignored', () => {
  const plan = planMissingChapters([3, 1, 2, 2, 0, -4, 3], 3);
  assert.deepEqual(plan.missing, []);
  assert.deepEqual(plan.toFetch, []);
});

test('chapters stored beyond the advertised latest do not create work', () => {
  assert.deepEqual(planMissingChapters(range(1, 12), 10).missing, []);
});

test('a zero cap plans nothing; an unknown latest plans nothing', () => {
  assert.deepEqual(planMissingChapters([], 5, { max: 0 }).toFetch, []);
  assert.deepEqual(planMissingChapters([], 0).missing, []);
});

test('formatRanges compresses runs', () => {
  assert.equal(formatRanges([]), '-');
  assert.equal(formatRanges([9, 1, 2, 3, 7, 10]), '1-3, 7, 9-10');
  assert.equal(formatRanges([1, 3, 5, 7], 2), '1, 3, … (+2 ranges)');
});

test('nextScheduledRun picks the next hour:minute UTC strictly after now', () => {
  assert.equal(nextScheduledRun(new Date('2026-10-16T03:59:00Z'), 4, 0).toISOString(), '2026-10-16T04:00:00.000Z');
  assert.equal(nextScheduledRun(new Date('2026-10-16T04:00:00Z'), 4, 0).toISOString(), '2026-10-17T04:00:00.000Z');
  assert.equal(nextScheduledRun(new Date('2026-12-31T23:30:00Z'), 4, 15).toISOString(), '2027-01-01T04:15:00.000Z');
});

test('isRunOverdue', () => {
  const now = new Date('2026-10-16T12:00:00Z');
  assert.equal(isRunOverdue(null, now, 24), true);
  assert.equal(isRunOverdue(new Date('2026-10-15T13:00:00Z'), now, 24), false);
  assert.equal(isRunOverdue(new Date('2026-10-15T12:00:00Z'), now, 24), true);
});

const row: NovelRow = {
  id: 1,
  title: 'Shadow Slave',
  novelUrl: 'https://novelfire.net/book/shadow-slave',
  author: 'Guiltythree',
  rank: '1',
  totalChapters: '3215',
  views: '71.7M',
  bookmarks: '29.3K',
  status: 'Ongoing',
  genres: ['Action', 'Adventure'],
  summary: 'Growing up in poverty, Sunny never expected anything good from life. Show More',
  chaptersUrl: 'https://novelfire.net/book/shadow-slave/chapters',
  imageUrl: 'https://novelfire.net/server-1/shadow-slave.jpg',
  rating: 4.5,
  lastScraped: null
};

const meta: NovelPageMeta = {
  title: 'Shadow Slave (renamed)',
  author: 'Guiltythree',
  rank: '1',
  totalChapters: '3216',
  views: '71.8M',
  bookmarks: null,
  status: 'Ongoing',
  genres: ['Action', 'Adventure'],
  summary: 'Growing up in poverty,  Sunny never expected anything good from life.',
  imageUrl: 'https://novelfire.net/server-1/shadow-slave.jpg',
  rating: 4.6,
  chaptersUrl: 'https://novelfire.net/book/shadow-slave/chapters'
};

test('diffNovelMeta reports only changed columns and never blanks or retitles', () => {
  assert.deepEqual(diffNovelMeta(row, meta), { total_chapters: '3216', views: '71.8M', rating: 4.6 });
});

test('diffNovelMeta picks up real summary, genre, and status changes', () => {
  const changes = diffNovelMeta(row, { ...meta, summary: 'A new blurb.', genres: ['Action'], status: 'Completed' });
  assert.equal(changes.summary, 'A new blurb.');
  assert.deepEqual(changes.genres, ['Action']);
  assert.equal(changes.status, 'Completed');
});

test('summaryKey ignores whitespace and the trailing "Show More"', () => {
  assert.equal(summaryKey('a b  c Show More'), summaryKey('a\nb c'));
  assert.equal(summaryKey('a b. Show More Show More'), summaryKey('a b.'));
  assert.notEqual(summaryKey('abc'), summaryKey('abd'));
});
