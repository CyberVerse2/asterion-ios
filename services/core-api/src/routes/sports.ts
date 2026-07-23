import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import {
  getSports,
  getMatchesBySport,
  getLiveMatches,
  resolveStreams,
  StreamSourceSchema,
  matchStore,
  getMatchById,
  badgeUrl,
  posterUrl,
} from "../lib/sports";

const sportQuerySchema = z.object({
  sport: z.string().min(1),
});

const streamBodySchema = z.object({
  matchId: z.string().min(1),
  sources: z.array(StreamSourceSchema),
  homeTeam: z.string(),
  awayTeam: z.string(),
});

export const sportsRoutes: FastifyPluginAsync = async (app) => {
  app.get("/api/sports", async () => {
    const sports = await getSports();
    return { success: true, data: sports };
  });

  app.get("/api/matches", async (request, reply) => {
    const parsed = sportQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({
        success: false,
        error: "sport query parameter is required.",
      });
    }

    const matches = await getMatchesBySport(parsed.data.sport);
    return { success: true, data: matches };
  });

  app.get("/api/matches/live", async () => {
    const live = await getLiveMatches();
    return { success: true, data: live.length ? live : null };
  });

  app.get("/api/matches/:id", async (request, reply) => {
    const params = z.object({ id: z.string().min(1) }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ success: false, error: "Invalid match id." });
    }

    const match = getMatchById(params.data.id);
    if (!match) {
      return reply.code(404).send({ success: false, error: "Match not found." });
    }

    return { success: true, data: match };
  });

  app.post("/api/streams", async (request, reply) => {
    const parsed = streamBodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        success: false,
        error: "Invalid request body.",
        issues: parsed.error.flatten(),
      });
    }

    const result = await resolveStreams(
      parsed.data.matchId,
      parsed.data.sources,
      parsed.data.homeTeam,
      parsed.data.awayTeam
    );

    if (!result.success) {
      return reply.code(404).send(result);
    }

    return result;
  });

  // Image proxy helpers
  app.get("/api/images/badge/:code", async (request, reply) => {
    const params = z.object({ code: z.string().min(1) }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ success: false, error: "Badge code required." });
    }
    const url = badgeUrl(params.data.code);
    if (!url) {
      return reply.code(400).send({ success: false, error: "No badge code provided." });
    }
    return { success: true, data: { url } };
  });

  app.get("/api/images/poster", async (request, reply) => {
    const query = z.object({ path: z.string().min(1) }).safeParse(request.query);
    if (!query.success) {
      return reply.code(400).send({ success: false, error: "path query parameter required." });
    }
    const url = posterUrl(query.data.path);
    return { success: true, data: { url } };
  });

  // Debug: list cached matches from in-memory store
  app.get("/api/matches/cached/:sport", async (request, reply) => {
    const params = z.object({ sport: z.string().min(1) }).safeParse(request.params);
    if (!params.success) {
      return reply.code(400).send({ success: false, error: "Invalid sport." });
    }
    const matches = matchStore.filter((m) => m.category === params.data.sport);
    return { success: true, data: matches };
  });
};
