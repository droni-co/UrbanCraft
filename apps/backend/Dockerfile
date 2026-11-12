# Contexto de build: raíz del monorepo (workspace de pnpm + pnpm-lock.yaml)
#   docker build -f apps/backend/Dockerfile .

# ---- Base con pnpm (versión de "packageManager" vía corepack) ----
FROM node:24-slim AS base
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/backend/package.json apps/backend/

# ---- Build ----
FROM base AS build
RUN pnpm install --frozen-lockfile --filter @urbancraft/backend
COPY apps/backend apps/backend
# .env de relleno para que los hooks del build puedan arrancar la app; no se usa en runtime
RUN cd apps/backend && printf '%s\n' \
  TZ=UTC PORT=3333 HOST=0.0.0.0 NODE_ENV=production LOG_LEVEL=info \
  APP_KEY=build-only-placeholder-key-000000 APP_URL=http://localhost:3333 \
  SESSION_DRIVER=cookie DB_HOST=localhost DB_PORT=5432 DB_USER=build DB_DATABASE=build > .env
RUN pnpm --filter @urbancraft/backend build
# Dependencias de producción autocontenidas (sin symlinks al workspace)
RUN pnpm --filter @urbancraft/backend deploy --prod --legacy /prod

# ---- Producción ----
FROM node:24-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /prod/node_modules ./node_modules
COPY --from=build /app/apps/backend/build ./
COPY apps/backend/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
USER node
EXPOSE 3333
ENTRYPOINT ["entrypoint.sh"]
CMD ["node", "bin/server.js"]
