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

# ---- Versión web del juego (/play): export de Godot ----
# GODOT_VERSION debe ser la misma con la que se trabaja el proyecto (godot --version).
FROM debian:bookworm-slim AS game-web
ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip gzip \
  && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip \
    https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
  && unzip -q /tmp/godot.zip -d /tmp/godot && mv /tmp/godot/Godot_v* /usr/local/bin/godot && rm -rf /tmp/godot*
# De las plantillas (~1,3 GB) solo se guarda la web sin hilos; la capa queda en caché.
RUN T=/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable && mkdir -p $T \
  && curl -fsSL -o /tmp/templates.tpz \
    https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
  && unzip -q -j /tmp/templates.tpz templates/web_nothreads_release.zip templates/version.txt -d $T \
  && rm /tmp/templates.tpz
COPY apps/game /game
RUN mkdir -p /out && godot --headless --path /game --import \
  && godot --headless --path /game --export-release Web /out/index.html \
  && cd /out && gzip -kf9 *.wasm *.js

# ---- Producción ----
FROM node:24-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /prod/node_modules ./node_modules
COPY --from=build /app/apps/backend/build ./
COPY --from=game-web /out ./public/play
COPY apps/backend/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
USER node
EXPOSE 3333
ENTRYPOINT ["entrypoint.sh"]
CMD ["node", "bin/server.js"]
