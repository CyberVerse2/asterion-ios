import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import {
  getChapterById,
  getChapterByNovelIdAndNumber,
  getNovelById,
  listChaptersByNovelId,
  listNovels,
} from "../lib/content";

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

const novelsQuerySchema = z.object({
  search: z.string().trim().optional(),
  page: z.coerce.number().int().positive().optional(),
  pageSize: z.coerce.number().int().positive().optional(),
  limit: z.coerce.number().int().positive().optional(),
  offset: z.coerce.number().int().min(0).optional(),
});

function parseListOptions(query: z.infer<typeof novelsQuerySchema>) {
  const isPageBased = query.page !== undefined || query.pageSize !== undefined;
  const isOffsetBased = query.limit !== undefined || query.offset !== undefined;

  if (isPageBased && isOffsetBased) {
    return { error: 'Use either "page/pageSize" or "limit/offset", not both.' as const };
  }

  if (isPageBased) {
    const page = query.page ?? 1;
    const pageSize = Math.min(query.pageSize ?? DEFAULT_LIMIT, MAX_LIMIT);
    return {
      options: {
        limit: pageSize,
        offset: (page - 1) * pageSize,
        page,
        pageSize,
      },
    };
  }

  const limit = Math.min(query.limit ?? DEFAULT_LIMIT, MAX_LIMIT);
  const offset = query.offset ?? 0;
  return {
    options: {
      limit,
      offset,
      page: Math.floor(offset / limit) + 1,
      pageSize: limit,
    },
  };
}

function buildMeta({
  count,
  total,
  page,
  pageSize,
  limit,
  offset,
  novelId,
}: {
  count: number;
  total: number;
  page: number;
  pageSize: number;
  limit: number;
  offset: number;
  novelId?: number;
}) {
  return {
    ...(novelId !== undefined ? { novelId: String(novelId) } : {}),
    count,
    total,
    page,
    pageSize,
    totalPages: total === 0 ? 0 : Math.ceil(total / pageSize),
    hasNextPage: offset + count < total,
    hasPreviousPage: page > 1,
    limit,
    offset,
  };
}

export const contentRoutes: FastifyPluginAsync = async (app) => {
  app.get("/novels", async (request, reply) => {
    const parsed = novelsQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: "Invalid novels query.", issues: parsed.error.flatten() });
    }

    const { options, error } = parseListOptions(parsed.data);
    if (!options) {
      return reply.code(400).send({ error });
    }

    const result = await listNovels({
      limit: options.limit,
      offset: options.offset,
      ...(parsed.data.search ? { search: parsed.data.search } : {}),
    });

    return {
      data: result.data,
      meta: buildMeta({
        count: result.data.length,
        total: result.total,
        page: options.page,
        pageSize: options.pageSize,
        limit: options.limit,
        offset: options.offset,
      }),
    };
  });

  app.get("/novels/:id", async (request, reply) => {
    const params = z.object({ id: z.coerce.number().int().positive() }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: "Novel id must be a positive integer." });
    }

    const novel = await getNovelById(params.data.id);
    if (!novel) {
      return reply.code(404).send({ error: `Novel with id ${params.data.id} not found.` });
    }

    return { data: novel };
  });

  app.get("/novels/:id/chapters", async (request, reply) => {
    const params = z.object({ id: z.coerce.number().int().positive() }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: "Novel id must be a positive integer." });
    }

    const query = novelsQuerySchema.safeParse(request.query);
    if (!query.success) {
      return reply.code(400).send({ error: "Invalid chapters query.", issues: query.error.flatten() });
    }

    const novel = await getNovelById(params.data.id);
    if (!novel) {
      return reply.code(404).send({ error: `Novel with id ${params.data.id} not found.` });
    }

    const { options, error } = parseListOptions(query.data);
    if (!options) {
      return reply.code(400).send({ error });
    }

    const result = await listChaptersByNovelId(params.data.id, {
      limit: options.limit,
      offset: options.offset,
    });

    return {
      data: result.data,
      meta: buildMeta({
        novelId: params.data.id,
        count: result.data.length,
        total: result.total,
        page: options.page,
        pageSize: options.pageSize,
        limit: options.limit,
        offset: options.offset,
      }),
    };
  });

  app.get("/novels/:id/chapters/:chapterNumber", async (request, reply) => {
    const params = z
      .object({
        id: z.coerce.number().int().positive(),
        chapterNumber: z.coerce.number().int().positive(),
      })
      .safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: "Novel id and chapter number must be positive integers." });
    }

    const novel = await getNovelById(params.data.id);
    if (!novel) {
      return reply.code(404).send({ error: `Novel with id ${params.data.id} not found.` });
    }

    const chapter = await getChapterByNovelIdAndNumber(params.data.id, params.data.chapterNumber);
    if (!chapter) {
      return reply
        .code(404)
        .send({ error: `Chapter ${params.data.chapterNumber} not found for novel ${params.data.id}.` });
    }

    return { data: chapter };
  });

  app.get("/chapters/:id", async (request, reply) => {
    const params = z.object({ id: z.coerce.number().int().positive() }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ error: "Chapter id must be a positive integer." });
    }

    const chapter = await getChapterById(params.data.id);
    if (!chapter) {
      return reply.code(404).send({ error: `Chapter with id ${params.data.id} not found.` });
    }

    return { data: chapter };
  });
};
