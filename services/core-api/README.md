# Asterion Backend

Node + Fastify + Drizzle API for user data persistence.

## Run locally

1. Copy env file:
   - `cp .env.example .env`
2. Update `DATABASE_URL` and Clerk values in `.env`.
3. Push Drizzle schema:
   - `npm run db:push`
5. Start dev server:
   - `npm run dev`
   - (uses `nodemon` + `tsx`)

Healthcheck:
- `GET /health`

## Dokploy deploy

1. Create an application from this repository.
2. Set the build context to `backend`.
3. Select Dockerfile as the build type and use `Dockerfile`.
4. Set the runtime variables from `.env.example`, with production values for
   PostgreSQL and Clerk.
5. Expose container port `3001` and use `/health` for health checks.

The image compiles the API during the build. On startup it applies pending
database migrations before accepting traffic.

## Smoke test

- Start backend, then run:
  - `npm run smoke`
- Optional remote target:
  - `SMOKE_BASE_URL=https://api.example.com npm run smoke`
