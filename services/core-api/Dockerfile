FROM node:22-bookworm-slim AS build

ENV PUPPETEER_SKIP_DOWNLOAD=true

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build \
    && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production \
    API_HOST=0.0.0.0 \
    API_PORT=3001

WORKDIR /app

RUN groupadd --system asterion \
    && useradd --system --gid asterion --home-dir /app asterion

COPY --from=build --chown=asterion:asterion /app/package.json /app/package-lock.json ./
COPY --from=build --chown=asterion:asterion /app/node_modules ./node_modules
COPY --from=build --chown=asterion:asterion /app/dist ./dist
COPY --chown=asterion:asterion drizzle ./drizzle
COPY --chown=asterion:asterion scripts ./scripts

USER asterion

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:' + process.env.API_PORT + '/health').then((response) => { if (!response.ok) process.exit(1) }).catch(() => process.exit(1))"

CMD ["sh", "-c", "npm run db:migrate:deploy && exec npm run start"]
