import * as cheerio from 'cheerio';

/** Metadata scraped from a novelfire.net book page (`/book/<slug>`). */
export interface NovelPageMeta {
  title: string | null;
  author: string | null;
  rank: string | null;
  totalChapters: string | null;
  views: string | null;
  bookmarks: string | null;
  status: string | null;
  genres: string[];
  summary: string | null;
  imageUrl: string | null;
  rating: number | null;
  chaptersUrl: string | null;
}

/** What the first page of `/book/<slug>/chapters` tells us. */
export interface ChapterListInfo {
  title: string | null;
  status: string | null;
  imageUrl: string | null;
  /** Highest chapter URL number (`/chapter-<n>`) the site advertises, or null when unknown. */
  latestChapterNumber: number | null;
  latestChapterTitle: string | null;
  /** Chapter URL numbers linked from this page of the list. */
  chapterNumbersOnPage: number[];
}

export interface ChapterPage {
  title: string | null;
  /** Sanitised inner HTML of `#content` (ads and scripts removed). Empty string when missing. */
  contentHtml: string;
  /** Visible text length of the content, whitespace collapsed. */
  textLength: number;
}

const CHAPTER_HREF = /\/chapter-(\d+)(?:[/?#]|$)/;

export function chapterNumberFromUrl(href: string | undefined | null): number | null {
  if (!href) return null;
  const match = CHAPTER_HREF.exec(href);
  if (!match?.[1]) return null;
  const value = Number(match[1]);
  return Number.isSafeInteger(value) && value > 0 ? value : null;
}

function clean(text: string | undefined | null): string | null {
  if (text == null) return null;
  const value = text.replace(/\s+/g, ' ').trim();
  return value.length > 0 ? value : null;
}

function absolute(href: string | undefined | null, base: string): string | null {
  if (!href) return null;
  try {
    return new URL(href, base).href;
  } catch {
    return null;
  }
}

function isNotFoundPage($: cheerio.CheerioAPI): boolean {
  return /page not found/i.test($('title').first().text());
}

function parseRating(raw: string | undefined | null): number | null {
  if (!raw) return null;
  const value = Number.parseFloat(raw.trim());
  return Number.isFinite(value) && value >= 0 && value <= 10 ? value : null;
}

function ratingFromLdJson($: cheerio.CheerioAPI): number | null {
  let rating: number | null = null;
  $('script[type="application/ld+json"]').each((_, element) => {
    if (rating !== null) return;
    try {
      const data = JSON.parse($(element).text()) as { '@type'?: string; ratingValue?: string | number };
      if (data['@type'] === 'AggregateRating') {
        rating = parseRating(String(data.ratingValue ?? ''));
      }
    } catch {
      // ignore malformed JSON-LD
    }
  });
  return rating;
}

/** Parses a novel's book page. Returns null when the page is novelfire's "Page Not Found" shell. */
export function parseNovelPage(html: string, pageUrl: string): NovelPageMeta | null {
  const $ = cheerio.load(html);
  if (isNotFoundPage($)) return null;

  const title = clean($('h1.novel-title').first().text());
  if (!title) return null;

  const stats: Record<string, string | null> = {};
  $('.header-stats span').each((_, element) => {
    const label = clean($(element).find('small').first().text())?.toLowerCase();
    if (label) stats[label] = clean($(element).find('strong').first().text());
  });

  const summaryNode = $('.summary .content').first().clone();
  summaryNode.find('.expand, script, style').remove();
  // Some summaries start with bare text before the first <p>, so keep every text node and only add
  // a space at paragraph/line breaks. Joined with spaces (the stored format the apps already
  // render), minus "Show More" (the button, and copies baked into some summaries' text).
  summaryNode.find('br').replaceWith(' ');
  summaryNode.find('p').prepend(' ').append(' ');
  const summary = clean(summaryNode.text().replace(/(\s*Show More)+\s*$/i, ''));

  const coverImg = $('figure.cover img').first();
  const imageUrl =
    absolute(coverImg.attr('src') ?? coverImg.attr('data-src'), pageUrl) ??
    absolute($('meta[property="og:image"]').attr('content'), pageUrl);

  const rankText = clean($('.rating .rank strong').first().text() || $('.rank strong').first().text());

  return {
    title,
    author: clean($('.author [itemprop="author"]').first().text()),
    rank: rankText ? rankText.replace(/^rank\s*/i, '').trim() || null : null,
    totalChapters: stats['chapters']?.replace(/,/g, '') ?? null,
    views: stats['views'] ?? null,
    bookmarks: stats['bookmarked'] ?? stats['bookmarks'] ?? null,
    status: stats['status'] ?? null,
    genres: $('.categories ul a')
      .map((_, element) => clean($(element).text()))
      .get()
      .filter((value): value is string => Boolean(value)),
    summary,
    imageUrl,
    rating: parseRating($('strong.nub').first().text()) ?? ratingFromLdJson($),
    chaptersUrl: absolute($('a.chapter-latest-container').attr('href'), pageUrl)
  };
}

/** Parses page 1 of a novel's chapter list. Returns null for the "Page Not Found" shell. */
export function parseChapterListPage(html: string, pageUrl: string): ChapterListInfo | null {
  const $ = cheerio.load(html);
  if (isNotFoundPage($)) return null;

  const root = $('#chapter-list-page');
  if (root.length === 0) return null;

  const chapterNumbersOnPage = root
    .find('ul.chapter-list a[href]')
    .map((_, element) => chapterNumberFromUrl($(element).attr('href')))
    .get()
    .filter((value): value is number => typeof value === 'number');

  // "Latest Release: <a href=/book/x/chapter-N>" is the authoritative latest URL number.
  let latestChapterNumber: number | null = null;
  let latestChapterTitle: string | null = null;
  root.find('header p').each((_, element) => {
    if (latestChapterNumber !== null) return;
    const paragraph = $(element);
    if (!/latest release/i.test(paragraph.text())) return;
    const link = paragraph.find('a[href]').first();
    latestChapterNumber = chapterNumberFromUrl(link.attr('href'));
    latestChapterTitle = clean(link.attr('title') ?? link.text());
  });

  if (latestChapterNumber === null) {
    const max = Number($('#gotochapno').attr('max'));
    if (Number.isSafeInteger(max) && max > 0) latestChapterNumber = max;
  }
  if (latestChapterNumber === null && chapterNumbersOnPage.length > 0) {
    latestChapterNumber = Math.max(...chapterNumbersOnPage);
  }

  const cover = root.find('figure.novel-cover img').first();
  return {
    title: clean(root.find('header h1').first().text()),
    status: clean(root.find('header .status').first().text()),
    imageUrl: absolute(cover.attr('src') ?? cover.attr('data-src'), pageUrl),
    latestChapterNumber,
    latestChapterTitle,
    chapterNumbersOnPage
  };
}

const JUNK_SELECTORS = [
  'script',
  'style',
  'noscript',
  'iframe',
  'ins',
  'form',
  'button',
  '[class*="bg-ppb"]',
  '[id*="bg-ppb"]',
  '[class*="bg-container"]',
  '[class*="adsbox"]',
  '[class*="advert"]'
].join(', ');

/** Parses a chapter page. Returns null for novelfire's "Page Not Found" shell. */
export function parseChapterPage(html: string): ChapterPage | null {
  const $ = cheerio.load(html);
  if (isNotFoundPage($)) return null;

  const content = $('#content').first();
  let title = clean($('h1 span.chapter-title').first().text());
  if (!title) {
    // "<Novel> - Chapter 12 - Novel Fire"
    const parts = $('title').first().text().split(' - ');
    title = parts.length >= 3 ? clean(parts.slice(1, -1).join(' - ')) : null;
  }

  if (content.length === 0) {
    return { title, contentHtml: '', textLength: 0 };
  }

  content.find(JUNK_SELECTORS).remove();
  // Ad slots leave nested empty wrappers behind; drop elements with no text and no media.
  for (let pass = 0; pass < 6; pass++) {
    const empties = content
      .find('div, span, section')
      .filter((_, element) => {
        const node = $(element);
        return node.text().trim().length === 0 && node.find('img, picture, svg, video').length === 0;
      });
    if (empties.length === 0) break;
    empties.remove();
  }

  const contentHtml = (content.html() ?? '').trim();
  const textLength = content.text().replace(/\s+/g, ' ').trim().length;
  return { title, contentHtml, textLength };
}

export function isEmptyChapter(page: ChapterPage | null, minChars: number): boolean {
  return !page || page.contentHtml.length === 0 || page.textLength < minChars;
}
