import type { FastifyPluginAsync } from "fastify";
import { sql } from "drizzle-orm";
import { db } from "../lib/db";

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get("/health", async () => {
    await db.execute(sql`SELECT 1`);
    return { ok: true };
  });
};
