import cors from "@fastify/cors";
import Fastify from "fastify";
import { env } from "./config/env";
import { healthRoutes } from "./routes/health";
import { authPlugin } from "./plugins/auth";
import { meRoutes } from "./routes/me";

export function buildApp() {
  const isDevelopment = env.NODE_ENV === "development";
  const app = Fastify({
    logger: isDevelopment
      ? {
          level: "debug",
          transport: {
            target: "pino-pretty",
            options: {
              colorize: true,
              translateTime: "SYS:standard",
              ignore: "pid,hostname",
              singleLine: true,
            },
          },
        }
      : true,
  });

  app.register(cors, {
    origin: true,
  });

  app.register(authPlugin);
  app.register(healthRoutes);
  app.register(meRoutes);

  return app;
}
