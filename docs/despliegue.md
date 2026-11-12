# Despliegue del servidor

El servidor (`apps/backend`) se despliega con Docker detrás de
[nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) +
[acme-companion](https://github.com/nginx-proxy/acme-companion), que ya deben
estar corriendo en la máquina con la red externa `nginx-proxy`.

- `apps/backend/Dockerfile`: imagen multi-stage (build de AdonisJS con pnpm y
  dependencias de producción vía `pnpm deploy`). Contexto: raíz del monorepo.
- La imagen incluye la **versión web del juego** en `/play` (etapa `game-web`: exporta con Godot al construir; ver [exportar.md](exportar.md#4-web-urbancraftdronivipplay)).
- `apps/backend/docker/entrypoint.sh`: ejecuta las migraciones pendientes antes
  de arrancar (`RUN_MIGRATIONS=false` para saltarlas).
- `docker-compose.prod.yml`: `api` + `postgres` (PostGIS) en una red privada;
  solo `api` se conecta a `nginx-proxy` (`VIRTUAL_HOST` / `LETSENCRYPT_HOST`).
  La base de datos no publica puertos en el host.

## Primer despliegue

```sh
cp .env.deploy.example .env.deploy
# Rellenar APP_KEY (openssl rand -base64 32), DB_PASSWORD y, si aplica, Google OAuth
docker compose -f docker-compose.prod.yml --env-file .env.deploy up -d --build
```

El certificado de Let's Encrypt se emite solo en ~1 minuto si el DNS del
dominio apunta a la máquina.

## Actualizar

```sh
git pull
docker compose -f docker-compose.prod.yml --env-file .env.deploy up -d --build api
```

## Operación

```sh
# Logs
docker compose -f docker-compose.prod.yml --env-file .env.deploy logs -f api
# Comandos ace (p. ej. pregenerar el mapa)
docker compose -f docker-compose.prod.yml --env-file .env.deploy exec api node ace map:pregenerate
# Backup de la base de datos
docker compose -f docker-compose.prod.yml --env-file .env.deploy exec -T postgres \
  pg_dump -U urbancraft urbancraft | gzip > urbancraft-$(date +%F).sql.gz
```

## Cliente

Los builds de escritorio y Android apuntan a `https://urbancraft.droni.vip` por defecto
(ajuste `urbancraft/network/api_base_url`; `--local` para el backend local). La versión
web usa el mismo dominio desde el que se sirve (`/play`). El WebSocket va por `wss://…/ws`.

Para el login con Google en producción, añadir en Google Cloud Console el URI de
redireccionamiento `https://urbancraft.droni.vip/auth/google/callback`.
