# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS build

WORKDIR /app

COPY services/novels/package.json services/novels/package-lock.json ./
RUN npm ci

COPY services/novels/tsconfig.json ./
COPY services/novels/src ./src
RUN npm run build \
    && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8080

WORKDIR /app

RUN groupadd --system asterion \
    && useradd --system --gid asterion --home-dir /app asterion

COPY --from=build --chown=asterion:asterion /app/package.json ./
COPY --from=build --chown=asterion:asterion /app/node_modules ./node_modules
COPY --from=build --chown=asterion:asterion /app/dist ./dist

USER asterion

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/health').then((response) => { if (!response.ok) process.exit(1) }).catch(() => process.exit(1))"

# Openship may override this with the service command; keep the two identical.
CMD ["node", "dist/server.js"]
