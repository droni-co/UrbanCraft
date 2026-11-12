# Inicio de sesión con Google

El jugador crea su cuenta (o entra) con su cuenta de Google. **Hace falta una sesión para jugar**: el botón **Jugar** de la pantalla inicial está deshabilitado hasta iniciar sesión, el mundo devuelve a la pantalla inicial si no hay sesión, y cerrar sesión (o que caduque) también. Con una sesión guardada se puede entrar sin conexión al mapa de demostración.

La primera vez se crea la cuenta con un apodo inicial (por ejemplo `Ana4821`), que se puede cambiar en **Menú → Cuenta**.

## Usuarios de prueba (depuración)

Para depurar y para pruebas automáticas no hace falta Google:

- **Pantalla inicial**, en builds de depuración: campo de nombre + **Entrar como usuario de prueba**.
- **Al arrancar:** `godot --path apps/game -- --dev-login=ana`. Sin nombre usa `tester`.
- **Backend local:** el juego usa la nube por defecto; añade `--local` (`-- --local --dev-login=ana`) o `--api-url=http://localhost:3334` para otro.
- **API:** `POST /api/v1/auth/dev/login { "name": "ana" }` devuelve `{ data: { user, token } }`.

Cada nombre es siempre el mismo usuario (`ana@dev.urbancraft.test`, apodo `ana` si está libre), así que sirve para probar con varios jugadores.

Solo funciona si se cumplen las tres condiciones:
1. `DEV_LOGIN_ENABLED=true` en `apps/backend/.env`.
2. `NODE_ENV` distinto de `production` (en producción está apagado aunque la variable diga `true`).
3. La petición sale de la misma máquina: conexión loopback y **sin cabeceras de proxy**. Un túnel como cloudflared también conecta por `127.0.0.1`, pero añade `X-Forwarded-For` / `CF-Connecting-IP`, así que no se puede usar desde fuera.

Si no se cumplen, la ruta responde 404 y `GET /api/v1/auth/methods` no la anuncia. Para borrar los usuarios de prueba: `DELETE FROM users WHERE email LIKE '%@dev.urbancraft.test'`.

## Configuración (una vez)

1. Entra a [Google Cloud Console](https://console.cloud.google.com/) y crea un proyecto (o usa uno existente).
2. **APIs y servicios → Pantalla de consentimiento de OAuth** (o "Google Auth Platform → Branding"):
   - Tipo de usuario: **Externo**.
   - Nombre de la app: `UrbanCraft`, email de soporte y email del desarrollador.
   - Alcances (scopes): `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`. No hacen falta otros, y con estos no se necesita verificación de Google.
   - Mientras la app esté en modo **Prueba**, solo pueden entrar los **usuarios de prueba** que agregues ahí (tu cuenta incluida). Para abrirla a todos, pulsa **Publicar app**.
3. **APIs y servicios → Credenciales → Crear credenciales → ID de cliente de OAuth**:
   - Tipo de aplicación: **Aplicación web** (no "Escritorio" ni "Android": quien habla con Google es el backend).
   - **URIs de redireccionamiento autorizados**: `http://localhost:3333/auth/google/callback`
   - Los "Orígenes de JavaScript autorizados" se pueden dejar vacíos.
4. Copia el **ID de cliente** y el **Secreto del cliente** en `apps/backend/.env`:

   ```bash
   GOOGLE_CLIENT_ID=1234567890-abc123.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=GOCSPX-...
   ```

5. Reinicia el backend (`pnpm dev` o `node ace serve --hmr`). Los cambios de `.env` no se recargan en caliente.

El juego (Godot) **no necesita** ni el client id ni el secreto: solo habla con tu backend. El secreto nunca debe ir en el cliente ni en git (`.env` está en `.gitignore`).

### En producción o para probar en el móvil

Google solo acepta redirecciones `https://` (salvo `http://localhost`) y no acepta IPs privadas como `192.168.x.x`. Para probar desde el teléfono, o en producción:

1. Expón el backend con un dominio HTTPS: tu servidor, o un túnel como `cloudflared tunnel --url http://localhost:3333`.
2. En `apps/backend/.env`: `APP_URL=https://tu-dominio` (el callback se deriva de ahí). Si el callback es otro, usa `GOOGLE_CALLBACK_URL=https://tu-dominio/auth/google/callback`.
3. Agrega esa URL en **URIs de redireccionamiento autorizados** de Google.
4. En Godot: **Proyecto → Configuración → urbancraft/network/api_base_url** = `https://tu-dominio`.

## Cómo funciona

El juego no puede recibir el callback de Google (no es una web y en móvil no tiene URL propia). Por eso usa un flujo de "consulta" (polling), parecido al *device flow* de las consolas, que funciona igual en PC, Android, iOS y web:

```
Juego                      Backend                         Navegador / Google
  │ POST /api/v1/auth/google/start │                               │
  │ ◄── loginId, pollSecret, url ─ │                               │
  │ abre url en el navegador ────────────────────────────────────► │
  │                                │ ◄── GET /auth/google/redirect │
  │                                │ ── 302 a Google (PKCE) ─────► │ el jugador elige su cuenta
  │                                │ ◄── GET /auth/google/callback │
  │                                │ crea o vincula la cuenta      │ "Ya puedes volver al juego"
  │ POST /auth/google/poll (cada 2 s)                               │
  │ ◄── 202 pendiente … 200 { user, token } ─                       │
```

- **`pollSecret`** solo viaja entre el juego y el backend, nunca en una URL. Quien vea la URL del navegador no puede recoger el token. El backend guarda solo su hash.
- **PKCE (S256)** y un `state` aleatorio protegen el canje del código. El `state` se renueva si se recarga la página.
- El login caduca a los **10 minutos**. El resultado se entrega **una sola vez**, y el token se crea en ese momento: nunca se guarda en la base de datos un token pendiente de recoger.
- Hay un **límite de 10 logins iniciados por minuto e IP** (en memoria, por instancia).
- El token de acceso dura **30 días** (`config/oauth.ts`). Cerrar sesión lo revoca en el servidor.
- **Cuentas:** se busca por el id de Google (`sub`). Si no existe pero hay una cuenta con el mismo email (registrada con contraseña) y Google confirma el email, se **vinculan**. Si Google no confirma el email, se rechaza (`email_in_use`).
- Las cuentas creadas con Google no tienen contraseña; el login por email y contraseña les responde `use_google`.

## Piezas

| Dónde | Qué |
| ----- | --- |
| `apps/backend/config/oauth.ts` | Client id/secret (desde `.env`), URLs de Google, tiempos, duración del token |
| `apps/backend/app/auth/google_client.ts` | Cliente HTTP de Google (canje del código + `userinfo`); abstracto para los tests |
| `apps/backend/app/services/oauth_login_service.ts` | El flujo: start / redirect / callback / poll, alta y vinculación de cuentas, apodos |
| `apps/backend/app/controllers/google_auth_controller.ts` | Rutas JSON del juego y páginas HTML del navegador |
| `apps/backend/database/migrations/1775*` | `users`: `google_id`, `avatar_url`, `nickname` (único, sin distinguir mayúsculas), `password` opcional · tabla `oauth_logins` |
| `apps/game/scripts/autoload/auth.gd` | Autoload `Auth`: login, sesión guardada en `user://session.cfg` (cifrada con el id del dispositivo), perfil, apodo, logout |
| `apps/game/scenes/ui/menu/account_section.gd` | UI de cuenta: en el menú (completa) y en la pantalla inicial (compacta) |

### Endpoints

| Método | Ruta | Descripción |
| ------ | ---- | ----------- |
| POST | `/api/v1/auth/google/start` | Inicia un login: `{ loginId, pollSecret, url, expiresIn, interval }` · 503 si no está configurado · 429 |
| POST | `/api/v1/auth/google/poll` | `{ loginId, pollSecret }` → 202 pendiente · 200 `{ data: { user, token, isNew } }` · 410 `{ error }` (`cancelled`, `expired`, `email_in_use`…) |
| GET | `/auth/google/redirect?login=` | (Navegador) redirige a Google |
| GET | `/auth/google/callback` | (Navegador) vuelta de Google; página "ya puedes volver al juego" |
| PATCH | `/api/v1/account/profile` | `{ nickname }` (3–20 letras, números o `_`) · 409 si está en uso |
| GET | `/api/v1/auth/methods` | `{ google, dev }`: qué métodos de login ofrece el servidor |
| POST | `/api/v1/auth/dev/login` | Solo desarrollo y en local: `{ name }` → usuario de prueba + token |

## Pendiente / ideas

- **Logo oficial de Google** en el botón: la guía de marca pide el logo "G". Se descarga de la página *Sign in with Google branding guidelines* y se pone como `icon` del botón (`MenuTheme`, variación `GoogleButton`).
- **Export web:** algunos navegadores bloquean la pestaña que se abre si no sale directamente de un clic. El botón "Abrir el navegador otra vez" lo resuelve.
- **Phishing de enlaces:** como en cualquier *device flow*, alguien podría enviarle a otra persona una URL de login iniciada por él. El enlace dura 10 minutos y sirve una sola vez. Si llega a ser un problema, se puede mostrar un código corto en el juego y en la página para que el jugador confirme que coinciden.
- Más proveedores (Apple es obligatorio en iOS si hay otros logins sociales): `GoogleOAuthClient` y `OAuthLoginService` están pensados para extenderse.
