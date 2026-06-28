import { pool } from "./db";

export interface ContentNovel {
  _id: string;
  title: string;
  novelUrl: string | null;
  author: string | null;
  rank: string | null;
  totalChapters: string | null;
  views: string | null;
  bookmarks: string | null;
  status: string | null;
  genres: string[];
  summary: string | null;
  chaptersUrl: string | null;
  imageUrl: string | null;
  rating: number | null;
  lastScraped: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface ContentChapter {
  _id: string;
  novelId: string;
  chapterNumber: number;
  url: string;
  title: string;
  content: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface ContentChapterListItem {
  _id: string;
  novelId: string;
  chapterNumber: number;
  url: string;
  title: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface PaginatedResult<T> {
  data: T[];
  total: number;
}

let contentSchemaEnsured = false;

function stringifyId(value: unknown): string {
  return String(value);
}

function mapNovelRow(row: Record<string, unknown>): ContentNovel {
  return {
    _id: stringifyId(row.id),
    title: String(row.title),
    novelUrl: row.novel_url as string | null,
    author: row.author as string | null,
    rank: row.rank as string | null,
    totalChapters: row.total_chapters as string | null,
    views: row.views as string | null,
    bookmarks: row.bookmarks as string | null,
    status: row.status as string | null,
    genres: Array.isArray(row.genres) ? row.genres.map(String) : [],
    summary: row.summary as string | null,
    chaptersUrl: row.chapters_url as string | null,
    imageUrl: row.image_url as string | null,
    rating: row.rating === null ? null : Number(row.rating),
    lastScraped: (row.last_scraped as Date | null) ?? null,
    createdAt: row.created_at as Date,
    updatedAt: row.updated_at as Date,
  };
}

function mapChapterRow(row: Record<string, unknown>): ContentChapter {
  return {
    _id: stringifyId(row.id),
    novelId: stringifyId(row.novel_id),
    chapterNumber: Number(row.chapter_number),
    url: String(row.url),
    title: String(row.title),
    content: String(row.content),
    createdAt: row.created_at as Date,
    updatedAt: row.updated_at as Date,
  };
}

function mapChapterListRow(row: Record<string, unknown>): ContentChapterListItem {
  return {
    _id: stringifyId(row.id),
    novelId: stringifyId(row.novel_id),
    chapterNumber: Number(row.chapter_number),
    url: String(row.url),
    title: String(row.title),
    createdAt: row.created_at as Date,
    updatedAt: row.updated_at as Date,
  };
}

export async function ensureContentSchema() {
  if (contentSchemaEnsured) {
    return;
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS novels (
      id BIGSERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      novel_url TEXT UNIQUE,
      author TEXT,
      rank TEXT,
      total_chapters TEXT,
      views TEXT,
      bookmarks TEXT,
      status TEXT,
      genres TEXT[] NOT NULL DEFAULT '{}',
      summary TEXT,
      chapters_url TEXT,
      image_url TEXT,
      rating DOUBLE PRECISION,
      last_scraped TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT novels_rating_range CHECK (rating IS NULL OR (rating >= 0 AND rating <= 10))
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS chapters (
      id BIGSERIAL PRIMARY KEY,
      novel_id BIGINT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
      chapter_number INTEGER NOT NULL,
      url TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (novel_id, chapter_number)
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_chapters_novel_id ON chapters (novel_id);
  `);

  contentSchemaEnsured = true;
}

export async function listNovels(options: {
  limit?: number;
  offset?: number;
  search?: string;
}): Promise<PaginatedResult<ContentNovel>> {
  await ensureContentSchema();

  const values: Array<string | number> = [];
  const conditions: string[] = [];

  if (options.search) {
    values.push(`%${options.search}%`);
    conditions.push(`(title ILIKE $${values.length} OR author ILIKE $${values.length})`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";

  const countResult = await pool.query<{ total: string }>(
    `
      SELECT COUNT(*)::BIGINT AS total
      FROM novels
      ${whereClause}
    `,
    values
  );

  const listValues = [...values];
  let limitClause = "";
  if (options.limit !== undefined) {
    listValues.push(options.limit);
    limitClause = `LIMIT $${listValues.length}`;
  }

  let offsetClause = "";
  if (options.offset !== undefined) {
    listValues.push(options.offset);
    offsetClause = `OFFSET $${listValues.length}`;
  }

  const rowsResult = await pool.query(
    `
      SELECT *
      FROM novels
      ${whereClause}
      ORDER BY id DESC
      ${limitClause}
      ${offsetClause}
    `,
    listValues
  );

  return {
    data: rowsResult.rows.map((row) => mapNovelRow(row)),
    total: Number(countResult.rows[0]?.total ?? 0),
  };
}

export async function getNovelById(novelId: number): Promise<ContentNovel | null> {
  await ensureContentSchema();

  const result = await pool.query(
    `
      SELECT *
      FROM novels
      WHERE id = $1
      LIMIT 1
    `,
    [novelId]
  );

  if (result.rows.length === 0) {
    return null;
  }

  return mapNovelRow(result.rows[0]);
}

export async function listChaptersByNovelId(
  novelId: number,
  options: { limit?: number; offset?: number }
): Promise<PaginatedResult<ContentChapterListItem>> {
  await ensureContentSchema();

  const values: number[] = [novelId];

  const countResult = await pool.query<{ total: string }>(
    `
      SELECT COUNT(*)::BIGINT AS total
      FROM chapters
      WHERE novel_id = $1
    `,
    values
  );

  const listValues = [...values];
  let limitClause = "";
  if (options.limit !== undefined) {
    listValues.push(options.limit);
    limitClause = `LIMIT $${listValues.length}`;
  }

  let offsetClause = "";
  if (options.offset !== undefined) {
    listValues.push(options.offset);
    offsetClause = `OFFSET $${listValues.length}`;
  }

  const result = await pool.query(
    `
      SELECT id, novel_id, chapter_number, url, title, created_at, updated_at
      FROM chapters
      WHERE novel_id = $1
      ORDER BY chapter_number ASC
      ${limitClause}
      ${offsetClause}
    `,
    listValues
  );

  return {
    data: result.rows.map((row) => mapChapterListRow(row)),
    total: Number(countResult.rows[0]?.total ?? 0),
  };
}

export async function getChapterByNovelIdAndNumber(
  novelId: number,
  chapterNumber: number
): Promise<ContentChapter | null> {
  await ensureContentSchema();

  const result = await pool.query(
    `
      SELECT *
      FROM chapters
      WHERE novel_id = $1 AND chapter_number = $2
      LIMIT 1
    `,
    [novelId, chapterNumber]
  );

  if (result.rows.length === 0) {
    return null;
  }

  return mapChapterRow(result.rows[0]);
}

export async function getChapterById(chapterId: number): Promise<ContentChapter | null> {
  await ensureContentSchema();

  const result = await pool.query(
    `
      SELECT *
      FROM chapters
      WHERE id = $1
      LIMIT 1
    `,
    [chapterId]
  );

  if (result.rows.length === 0) {
    return null;
  }

  return mapChapterRow(result.rows[0]);
}
