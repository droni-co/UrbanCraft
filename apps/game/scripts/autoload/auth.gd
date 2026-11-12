extends Node
## Sesión del jugador. Autoload "Auth".
##
## Inicio de sesión con Google sin que el juego reciba el callback de OAuth
## (funciona igual en PC, Android, iOS y web):
##   1. POST /api/v1/auth/google/start → loginId, pollSecret y una URL del backend.
##   2. Se abre esa URL en el navegador del sistema; el jugador elige su cuenta.
##   3. El juego consulta /api/v1/auth/google/poll hasta recibir su token.
## El client secret de Google vive solo en el backend (apps/backend/.env).
##
## La sesión se guarda en user://session.cfg (cifrada con el id del dispositivo)
## y se revalida al arrancar: si el token caducó o se revocó, se descarta.
## Hace falta una sesión para jugar (la pantalla inicial y el mundo lo exigen).
##
## Usuarios de prueba (depuración): login_dev("nombre"), el botón de la pantalla
## inicial en builds de depuración, o al arrancar:
##     godot --path apps/game -- --dev-login=ana
## Requiere DEV_LOGIN_ENABLED=true en el backend y solo funciona en local.

## Cambió la sesión: `user` vacío = sin sesión.
signal session_changed(user: Dictionary)
## Progreso del login: "starting", "waiting", "complete", "failed", "cancelled".
signal login_progress(state: String, message: String)
## Terminó la comprobación inicial (sesión guardada revalidada, --dev-login...).
signal startup_finished

const SESSION_PATH := "user://session.cfg"
const PREFIX := "/api/v1"

## Perfil del backend: id, nickname, fullName, email, avatarUrl, hasGoogle...
var user: Dictionary = {}
var is_logging_in := false
## true cuando terminó la comprobación inicial (ver startup_finished).
var startup_done := false
## Métodos de login que ofrece el servidor: { google: bool, dev: bool }.
var methods := {"google": false, "dev": false}
## URL de login en curso (para reabrir el navegador si se cerró).
var login_url := ""

## Cómo se abre el navegador (sustituible en pruebas automáticas).
var browser_opener := func(url: String) -> void: OS.shell_open(url)

var _cancel_requested := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()
	_startup.call_deferred()


## Espera a que termine la comprobación inicial de la sesión.
func wait_startup() -> void:
	if not startup_done:
		await startup_finished


func _startup() -> void:
	var dev_name := _dev_login_arg()
	if dev_name != "":
		var result := await login_dev(dev_name)
		if not result.ok:
			push_warning("--dev-login falló: %s" % result.message)
	elif is_signed_in():
		await refresh_profile()
	startup_done = true
	startup_finished.emit()


## Pregunta al servidor qué métodos de login hay (Google, usuarios de prueba).
func fetch_methods() -> Dictionary:
	var res := await Api.request_json(HTTPClient.METHOD_GET, PREFIX + "/auth/methods")
	if res.ok and res.data is Dictionary:
		methods = {"google": bool(res.data.get("google", false)), "dev": bool(res.data.get("dev", false))}
	return methods


## Entra con un usuario de prueba (solo servidores de desarrollo, en local).
## El mismo nombre entra siempre al mismo usuario. Devuelve { ok, message }.
func login_dev(dev_name := "tester") -> Dictionary:
	if is_logging_in:
		return {"ok": false, "message": "Ya hay un inicio de sesión en curso."}
	is_logging_in = true
	login_progress.emit("starting", "Entrando como %s…" % dev_name)
	var res := await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/auth/dev/login", {"name": dev_name})
	if res.ok:
		var data := _unwrap(res.data)
		_set_session(str(data.get("token", "")), data.get("user", {}))
		_finish_login("complete", "¡Hola, %s! (usuario de prueba)" % display_name(), {})
		return {"ok": true, "message": ""}
	var message := _error_message(res, "No se pudo entrar.")
	match res.status:
		404: message = "El servidor no permite usuarios de prueba (DEV_LOGIN_ENABLED=true, solo en local)."
		422: message = "Nombre inválido: hasta 20 letras, números o guion bajo."
	_finish_login("failed", message, res)
	return {"ok": false, "message": message}


func _dev_login_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg == "--dev-login":
			return "tester"
		if arg.begins_with("--dev-login="):
			return arg.substr("--dev-login=".length())
	return ""


func is_signed_in() -> bool:
	return Api.is_authenticated()


## Nombre para mostrar: apodo, nombre o email.
func display_name() -> String:
	for key in ["nickname", "fullName", "email"]:
		if user.get(key) is String and not str(user[key]).is_empty():
			return user[key]
	return "Jugador"


## Inicia sesión con Google. Devuelve { ok, error, message, is_new }.
## Mientras espera emite login_progress; cancel_login() lo interrumpe.
func login_with_google() -> Dictionary:
	if is_logging_in:
		return {"ok": false, "error": "in_progress", "message": "Ya hay un inicio de sesión en curso."}
	is_logging_in = true
	_cancel_requested = false
	login_progress.emit("starting", "Conectando…")

	var res := await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/auth/google/start", {})
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY:
		return _finish_login("failed", _error_message(res, "No se pudo iniciar sesión."), res)

	var login: Dictionary = res.data
	login_url = str(login.url)
	open_login_page()
	login_progress.emit("waiting", "Completa el inicio de sesión en el navegador…")

	var interval := maxf(float(login.get("interval", 2)), 1.0)
	var deadline := Time.get_ticks_msec() + int(float(login.get("expiresIn", 600)) * 1000.0)
	var body := {"loginId": login.loginId, "pollSecret": login.pollSecret}
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(interval, true).timeout
		if _cancel_requested:
			return _finish_login("cancelled", "Inicio de sesión cancelado.", {})
		var poll := await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/auth/google/poll", body)
		if poll.status == 202 or poll.status == 0 or poll.status >= 500:
			continue  # pendiente, o sin red / servidor caído un momento: seguir
		if poll.ok:
			var data: Dictionary = _unwrap(poll.data)
			_set_session(str(data.get("token", "")), data.get("user", {}))
			var result := _finish_login("complete", "¡Hola, %s!" % display_name(), {})
			result.is_new = bool(data.get("isNew", false))
			return result
		var error := _error_code(poll)
		var message := "Cancelaste el inicio de sesión." if error == "cancelled" \
			else _error_message(poll, "No se pudo iniciar sesión.")
		return _finish_login("cancelled" if error == "cancelled" else "failed", message, poll)
	return _finish_login("failed", "Se acabó el tiempo para iniciar sesión.", {})


func cancel_login() -> void:
	if is_logging_in:
		_cancel_requested = true


## Abre (o reabre) la página de login en el navegador del sistema.
func open_login_page() -> void:
	if not login_url.is_empty():
		browser_opener.call(login_url)


func logout() -> void:
	if is_signed_in():
		# Revoca el token en el servidor; si no hay red, igual se borra aquí.
		await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/account/logout")
	_set_session("", {})


## Vuelve a pedir el perfil (y comprueba que el token siga siendo válido).
func refresh_profile() -> bool:
	if not is_signed_in():
		return false
	var res := await Api.request_json(HTTPClient.METHOD_GET, PREFIX + "/account/profile")
	if res.status == 401:
		_set_session("", {})  # caducado o revocado
		return false
	if res.ok:
		_set_session(Api.token, _unwrap(res.data))
	return res.ok


## Cambia el apodo. Devuelve { ok, message }.
func update_nickname(nickname: String) -> Dictionary:
	var res := await Api.request_json(HTTPClient.METHOD_PATCH, PREFIX + "/account/profile", {"nickname": nickname})
	if res.ok:
		_set_session(Api.token, _unwrap(res.data))
		return {"ok": true, "message": "Apodo guardado."}
	match res.status:
		409: return {"ok": false, "message": "Ese apodo ya está en uso."}
		422: return {"ok": false, "message": "Usa de 3 a 20 letras, números o guion bajo."}
		401:
			_set_session("", {})
			return {"ok": false, "message": "Tu sesión caducó. Vuelve a iniciar sesión."}
	return {"ok": false, "message": _error_message(res, "No se pudo guardar el apodo.")}


## Cambia el personaje (skin) de la cuenta. Devuelve { ok, message }.
## Los jugadores cercanos lo ven al momento.
func update_skin(skin: String) -> Dictionary:
	var res := await Api.request_json(HTTPClient.METHOD_PATCH, PREFIX + "/account/profile", {"skin": skin})
	if res.ok:
		_set_session(Api.token, _unwrap(res.data))
		return {"ok": true, "message": "¡Listo! Ahora eres %s." % CharacterSkins.display_name(skin)}
	if res.status == 401:
		_set_session("", {})
		return {"ok": false, "message": "Tu sesión caducó. Vuelve a iniciar sesión."}
	return {"ok": false, "message": _error_message(res, "No se pudo cambiar el personaje.")}


# --- Interno ----------------------------------------------------------------------

func _finish_login(state: String, message: String, res: Dictionary) -> Dictionary:
	is_logging_in = false
	_cancel_requested = false
	login_url = ""
	login_progress.emit(state, message)
	var error := ""
	if state != "complete":
		error = _error_code(res) if not res.is_empty() else state
	return {"ok": state == "complete", "error": error, "message": message, "is_new": false}


func _set_session(new_token: String, new_user: Variant) -> void:
	Api.token = new_token
	user = new_user if new_user is Dictionary and not new_token.is_empty() else {}
	_save_session()
	session_changed.emit(user)


## Las respuestas con transformer vienen como { data: {...} }.
func _unwrap(data: Variant) -> Dictionary:
	if data is Dictionary:
		return data.get("data", data) if data.get("data") is Dictionary else data
	return {}


func _error_code(res: Dictionary) -> String:
	if res.get("data") is Dictionary and res.data.get("error") is String:
		return res.data.error
	return str(res.get("error", "error"))


func _error_message(res: Dictionary, fallback: String) -> String:
	if res.get("status", 0) == 0:
		return "Sin conexión con el servidor."
	if res.get("data") is Dictionary and res.data.get("message") is String:
		return res.data.message
	if res.get("status") == 503:
		return "El inicio de sesión con Google no está disponible en el servidor."
	return fallback


## Una sesión por servidor: el token de la nube no sirve en el backend local
## y viceversa, así que alternar entre ambos no cierra la otra sesión.
func _session_path() -> String:
	if Api.is_cloud():
		return SESSION_PATH
	return "user://session-%s.cfg" % Api.base_url.md5_text().substr(0, 8)


func _session_key() -> String:
	# En la web no hay id de dispositivo (y pedirlo registra un error).
	var id := "" if OS.has_feature("web") else OS.get_unique_id()
	return id if not id.is_empty() else "urbancraft-session"


func _save_session() -> void:
	if Api.token.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path()))
		return
	var cfg := ConfigFile.new()
	cfg.set_value("session", "token", Api.token)
	cfg.set_value("session", "user", user)
	cfg.save_encrypted_pass(_session_path(), _session_key())


func _load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(_session_path(), _session_key()) != OK:
		return
	Api.token = str(cfg.get_value("session", "token", ""))
	var saved: Variant = cfg.get_value("session", "user", {})
	user = saved if saved is Dictionary else {}
