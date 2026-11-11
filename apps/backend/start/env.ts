/*
|--------------------------------------------------------------------------
| Environment variables service
|--------------------------------------------------------------------------
|
| The `Env.create` method creates an instance of the Env service. The
| service validates the environment variables and also cast values
| to JavaScript data types.
|
*/

import { Env } from '@adonisjs/core/env'

export default await Env.create(new URL('../', import.meta.url), {
  // Node
  NODE_ENV: Env.schema.enum(['development', 'production', 'test'] as const),
  PORT: Env.schema.number(),
  HOST: Env.schema.string({ format: 'host' }),
  LOG_LEVEL: Env.schema.string(),

  // App
  APP_KEY: Env.schema.secret(),
  APP_URL: Env.schema.string({ format: 'url', tld: false }),

  // Session
  SESSION_DRIVER: Env.schema.enum(['cookie', 'memory', 'database'] as const),

  // Database (PostgreSQL + PostGIS)
  DB_HOST: Env.schema.string({ format: 'host' }),
  DB_PORT: Env.schema.number(),
  DB_USER: Env.schema.string(),
  DB_PASSWORD: Env.schema.string.optional(),
  DB_DATABASE: Env.schema.string(),
  DB_DEBUG: Env.schema.boolean.optional(),

  // Map generation (OpenStreetMap)
  OVERPASS_URL: Env.schema.string.optional({ format: 'url', tld: false }),
  MAP_WORKER_ENABLED: Env.schema.boolean.optional(),

  // Geolocalización por IP y geocodificación inversa (ciudad/país)
  NOMINATIM_URL: Env.schema.string.optional({ format: 'url', tld: false }),
  GEO_IP_ENABLED: Env.schema.boolean.optional(),

  // Inicio de sesión con Google (ver docs/login-google.md)
  GOOGLE_CLIENT_ID: Env.schema.string.optional(),
  GOOGLE_CLIENT_SECRET: Env.schema.string.optional(),
  GOOGLE_CALLBACK_URL: Env.schema.string.optional({ format: 'url', tld: false }),
  // Usuarios de prueba sin Google (solo desarrollo, solo desde esta máquina)
  DEV_LOGIN_ENABLED: Env.schema.boolean.optional(),
})
