import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import {
  getFootballMatches,
  getLiveFootballMatches,
  getPopularFootballMatches,
  resolveFootballStreams,
  StreamSourceSchema,
} from "../lib/sports";

const streamBodySchema = z.object({
  matchId: z.string().min(1),
  sources: z.array(StreamSourceSchema),
  homeTeam: z.string(),
  awayTeam: z.string(),
});

export const footballRoutes: FastifyPluginAsync = async (app) => {
  app.get("/api/football/matches", async () => ({
    success: true,
    data: await getFootballMatches(),
  }));

  app.get("/api/football/matches/live", async () => ({
    success: true,
    data: await getLiveFootballMatches(),
  }));

  app.get("/api/football/matches/popular", async () => ({
    success: true,
    data: await getPopularFootballMatches(),
  }));

  app.post("/api/football/streams", async (request, reply) => {
    const parsed = streamBodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        success: false,
        error: "Invalid stream request.",
        issues: parsed.error.flatten(),
      });
    }

    return resolveFootballStreams(
      parsed.data.matchId,
      parsed.data.sources,
      parsed.data.homeTeam,
      parsed.data.awayTeam
    );
  });
};
