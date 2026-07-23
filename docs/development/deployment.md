# Deployment paths

Each deployable service owns its Dockerfile, health check, environment example,
and runtime dependencies. Dokploy should use the following Dockerfile build
settings:

| Product | Docker context | Dockerfile | Port | Health check |
| --- | --- | --- | --- | --- |
| Core API | `services/core-api` | `Dockerfile` | `3001` | `/health` |
| Anime | `services/anime` | `Dockerfile` | `8080` | `/api/health` |
| Movies | `services/movies` | `Dockerfile` | `8080` | `/api/health` |
| Football | `services/football` | `Dockerfile` | `8080` | `/api/health` |

Runtime secrets belong in Dokploy's environment settings. Do not pass them as
Docker build arguments or copy local `.env` files into images.

The anime service requires `MEDIA_PROXY_SIGNING_KEY` and `REDIS_URL`. Redis
caches upstream catalog, detail, episode, and season responses and coordinates
concurrent cache misses across the Gunicorn workers. The core API requires
production PostgreSQL and Clerk values documented in its `.env.example`.
