import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  chapterNumberFromUrl,
  isEmptyChapter,
  parseChapterListPage,
  parseChapterPage,
  parseNovelPage
} from '../src/parse.js';

const fixture = (name: string) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8');

test('chapterNumberFromUrl reads the URL slug number', () => {
  assert.equal(chapterNumberFromUrl('/book/shadow-slave/chapter-3216'), 3216);
  assert.equal(chapterNumberFromUrl('https://novelfire.net/book/x/chapter-12?ref=1'), 12);
  assert.equal(chapterNumberFromUrl('/book/x/chapters'), null);
  assert.equal(chapterNumberFromUrl('/book/x/chapter-0'), null);
  assert.equal(chapterNumberFromUrl(undefined), null);
});

test('parseNovelPage extracts metadata from a book page', () => {
  const meta = parseNovelPage(fixture('novel-page.html'), 'https://novelfire.net/book/shadow-slave');
  assert.ok(meta);
  assert.equal(meta.title, 'Shadow Slave');
  assert.equal(meta.author, 'Guiltythree');
  assert.equal(meta.rank, '1');
  assert.equal(meta.totalChapters, '3216');
  assert.equal(meta.views, '71.8M');
  assert.equal(meta.bookmarks, '29.3K');
  assert.equal(meta.status, 'Ongoing');
  assert.deepEqual(meta.genres, ['Action', 'Adventure', 'Fantasy', 'Romance']);
  assert.equal(meta.rating, 4.5);
  assert.equal(meta.imageUrl, 'https://novelfire.net/server-1/shadow-slave.jpg');
  assert.equal(meta.chaptersUrl, 'https://novelfire.net/book/shadow-slave/chapters');
  assert.ok(meta.summary?.startsWith('Growing up in poverty, Sunny'));
  assert.ok(meta.summary?.includes('Awakened – an elite group'));
  assert.ok(!meta.summary?.includes('Show More'), 'summary must not include the "Show More" button');
});

test('parseNovelPage keeps bare summary text and drops "Show More" baked into the text', () => {
  const html = fixture('novel-page.html').replace(
    '<div class="content expand-wrapper"><p>Growing up',
    '<div class="content expand-wrapper">When Sunny opened his eyes,<br>he was poor.<p>Growing up'
  ).replace('supernatural powers. </p>', 'supernatural powers. Show More</p>');
  const meta = parseNovelPage(html, 'https://novelfire.net/book/shadow-slave');
  assert.ok(meta?.summary?.startsWith('When Sunny opened his eyes, he was poor. Growing up in poverty'));
  assert.ok(meta?.summary?.endsWith('gifted with supernatural powers.'));
});

test('parseNovelPage returns null for the "Page Not Found" shell', () => {
  assert.equal(parseNovelPage(fixture('not-found-404.html'), 'https://novelfire.net/book/x'), null);
});

test('parseChapterListPage finds the latest chapter from "Latest Release"', () => {
  const list = parseChapterListPage(
    fixture('chapter-list.html'),
    'https://novelfire.net/book/a-record-of-a-mortals-journey-to-immortality/chapters'
  );
  assert.ok(list);
  assert.equal(list.latestChapterNumber, 2456);
  assert.equal(list.latestChapterTitle, 'Bonus Immortal Realm 2');
  assert.equal(list.title, "A Record of a Mortal's Journey to Immortality");
  assert.equal(list.status, 'Completed');
  assert.deepEqual(list.chapterNumbersOnPage, [1, 2, 3, 4, 5]);
  assert.equal(list.imageUrl, 'https://novelfire.net/server-1/a-record-of-a-mortals-journey-to-immortality.jpg');
});

test('parseChapterListPage falls back to the go-to-chapter max, then to the page links', () => {
  const html = fixture('chapter-list.html');
  const withoutLatest = html.replace(/<p>Latest Release:[\s\S]*?<\/p>/, '');
  assert.equal(parseChapterListPage(withoutLatest, 'https://novelfire.net/book/x/chapters')?.latestChapterNumber, 2456);

  const withoutInput = withoutLatest.replace(/<input id="gotochapno"[^>]*>/, '');
  assert.equal(parseChapterListPage(withoutInput, 'https://novelfire.net/book/x/chapters')?.latestChapterNumber, 5);
});

test('parseChapterListPage returns null for the "Page Not Found" shell', () => {
  assert.equal(parseChapterListPage(fixture('not-found-404.html'), 'https://novelfire.net/book/x/chapters'), null);
});

test('parseChapterPage extracts the title and sanitised content', () => {
  const page = parseChapterPage(fixture('chapter-page.html'));
  assert.ok(page);
  assert.equal(page.title, 'Chapter 12');
  assert.ok(page.contentHtml.startsWith('<h4>Chapter 12: Crazy About Duels</h4>'));
  assert.ok(page.contentHtml.includes('Wu Liang was frustrated.'));
  for (const junk of ['<script', '<style', '<iframe', '<ins', 'bg-container', '<div']) {
    assert.ok(!page.contentHtml.includes(junk), `content should not contain ${junk}`);
  }
  assert.ok(page.textLength > 100);
  assert.equal(isEmptyChapter(page, 30), false);
});

test('parseChapterPage falls back to the <title> when the h1 has no chapter title', () => {
  const page = parseChapterPage(fixture('chapter-no-span-title.html'));
  assert.equal(page?.title, 'c-1 Power Levels And Abbreviations');
  assert.equal(isEmptyChapter(page, 30), false);
});

test('a chapter whose #content holds only ad markup is empty', () => {
  const page = parseChapterPage(fixture('chapter-empty.html'));
  assert.ok(page);
  assert.equal(page.title, 'Chapter 12');
  assert.equal(page.textLength, 0);
  assert.equal(isEmptyChapter(page, 30), true);
});

test('a chapter page without #content is empty', () => {
  const html = fixture('chapter-page.html').replace(/<div id="content"[\s\S]*<\/div><\/section>/, '</section>');
  const page = parseChapterPage(html);
  assert.ok(page);
  assert.equal(page.contentHtml, '');
  assert.equal(isEmptyChapter(page, 30), true);
});

test('the novelfire 500 "Page Not Found" chapter shell is not a chapter', () => {
  assert.equal(parseChapterPage(fixture('not-found-500.html')), null);
  assert.equal(isEmptyChapter(null, 30), true);
});
