/**
 * Página mínima que ve el jugador en el navegador al terminar (o fallar) el
 * inicio de sesión. Sin recursos externos.
 */
export function browserPage(opts: { title: string; message: string; ok: boolean }) {
  const color = opts.ok ? '#7ee787' : '#ff7b72'
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(opts.title)} · UrbanCraft</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 16px;
         background: #141820; color: #edf2f8; font: 16px/1.5 system-ui, sans-serif; }
  main { max-width: 420px; text-align: center; }
  h1 { font-size: 22px; margin: 0 0 8px; color: ${color}; }
  p { margin: 0; color: #a8b4c4; }
  .brand { font-weight: 700; letter-spacing: .04em; color: #4f9dff; margin-bottom: 24px; }
</style>
</head>
<body>
<main>
  <div class="brand">UrbanCraft</div>
  <h1>${escapeHtml(opts.title)}</h1>
  <p>${escapeHtml(opts.message)}</p>
</main>
</body>
</html>`
}

function escapeHtml(text: string) {
  return text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)
}
