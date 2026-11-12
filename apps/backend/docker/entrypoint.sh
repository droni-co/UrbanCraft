#!/bin/sh
set -e

# Migraciones pendientes antes de arrancar (desactivar con RUN_MIGRATIONS=false)
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  node ace migration:run --force
fi

exec "$@"
