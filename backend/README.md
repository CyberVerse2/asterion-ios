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

## Railway deploy

1. Create Railway project and attach a Postgres service.
2. Set env vars from `.env.railway.example`.
3. Deploy this `backend/` directory.
4. Railway uses `railway.json` to run:
   - builder: `RAILPACK`
   - build: `npm install && npm run build`
   - start: `npm run db:migrate:deploy && npm run start`

## Smoke test

- Start backend, then run:
  - `npm run smoke`
- Optional remote target:
  - `SMOKE_BASE_URL=https://your-api.up.railway.app npm run smoke`
