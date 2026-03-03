import "dotenv/config";
import { env } from "./config/env";
import { closeDb } from "./lib/db";
import { buildApp } from "./app";

async function start() {
  const app = buildApp();

  app.addHook("onClose", async () => {
    await closeDb();
  });

  try {
    await app.listen({ host: env.API_HOST, port: env.API_PORT });
  } catch (error) {
    app.log.error(error);
    process.exit(1);
  }
}

void start();
