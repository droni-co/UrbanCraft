extends Node
## Stats del jugador (hambre, experiencia, dinero…). Autoload "PlayerStats".
##
## El servidor es la fuente de verdad y define el catálogo
## (apps/backend/config/player_stats.ts): este nodo solo los lee y los reparte.
## Mientras el mundo está activo envía un latido cada ~60 s; con él el
## servidor aplica el desgaste (el hambre baja solo mientras se juega).
##
## Cada stat es un Dictionary: { key, label, kind ("meter" | "level" | "counter"),
## value, min, max, hud, order, icon, color, level? { level, current, needed, progress } }

## Llegaron stats nuevos (lista completa, ordenada).
signal updated(stats: Array)
## Cambió el valor de un stat (para animaciones: "+50", subir de nivel…).
signal stat_changed(key: String, old_value: float, new_value: float)
## Subió de nivel un stat de tipo "level".
signal level_up(key: String, level: int)

const PREFIX := "/api/v1/player"

var stats: Array = []
var _by_key := {}
var _active := false
var _heartbeat: Timer


func _ready() -> void:
	# Pausable: con el juego en pausa (menú abierto) no se envían latidos.
	_heartbeat = Timer.new()
	_heartbeat.wait_time = 60.0
	_heartbeat.timeout.connect(_send_heartbeat)
	add_child(_heartbeat)
	Auth.session_changed.connect(func(user: Dictionary) -> void:
		if user.is_empty():
			stop()
			_apply([]))


func has_stats() -> bool:
	return not stats.is_empty()


func get_stat(key: String) -> Dictionary:
	return _by_key.get(key, {})


## Valor actual de un stat (o `default` si no existe).
func value(key: String, default := 0.0) -> float:
	return float(get_stat(key).get("value", default))


## Empieza a seguir los stats (lo llama el mundo al entrar).
func start() -> void:
	_active = true
	await refresh()
	if _active:
		_heartbeat.start()


func stop() -> void:
	_active = false
	_heartbeat.stop()


func refresh() -> bool:
	if not Auth.is_signed_in():
		return false
	var res := await Api.request_json(HTTPClient.METHOD_GET, PREFIX + "/stats")
	return _handle(res)


## Solo desarrollo (servidor con DEV_LOGIN_ENABLED, en local): suma `delta` o fija `set_value`.
func dev_change(key: String, delta := 0.0, set_value: Variant = null) -> bool:
	var body := {"key": key}
	if set_value != null:
		body.value = set_value
	else:
		body.delta = delta
	var res := await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/stats/dev", body)
	return _handle(res)


## Texto corto para tooltips: "Hambre 87/100", "Nivel 3 (50/520 xp)", "Dinero 1.250".
static func describe(stat: Dictionary) -> String:
	var label: String = stat.get("label", stat.get("key", ""))
	match stat.get("kind"):
		"meter":
			return "%s %d/%d" % [label, roundi(stat.value), roundi(float(stat.max))]
		"level":
			var lv: Dictionary = stat.get("level", {})
			if int(lv.get("needed", 0)) == 0:
				return "Nivel %d (máximo)" % int(lv.get("level", 1))
			return "Nivel %d (%s/%s xp)" % [int(lv.level), format_number(lv.current), format_number(lv.needed)]
	return "%s %s" % [label, format_number(stat.get("value", 0))]


## 1250 → "1.250" (separador de miles en español).
static func format_number(n: Variant) -> String:
	var negative := float(n) < 0.0
	var digits := str(absi(roundi(float(n))))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if negative else "") + digits + out


# --- Interno ----------------------------------------------------------------------

func _send_heartbeat() -> void:
	if not _active or not Auth.is_signed_in():
		return
	var res := await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/heartbeat", {})
	if _handle(res) and res.data.get("nextHeartbeat") != null:
		_heartbeat.wait_time = maxf(float(res.data.nextHeartbeat), 10.0)


func _handle(res: Dictionary) -> bool:
	if res.status == 401:
		Auth.refresh_profile()  # el token caducó: Auth cierra la sesión
		return false
	if not res.ok or not (res.data is Dictionary) or not (res.data.get("stats") is Array):
		return false
	_apply(res.data.stats)
	return true


func _apply(new_stats: Array) -> void:
	var previous := _by_key
	stats = new_stats.duplicate()
	stats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("order", 0) < b.get("order", 0))
	_by_key = {}
	for s: Dictionary in stats:
		_by_key[s.key] = s
	updated.emit(stats)
	for s: Dictionary in stats:
		var old: Dictionary = previous.get(s.key, {})
		if old.is_empty():
			continue
		if not is_equal_approx(float(old.value), float(s.value)):
			stat_changed.emit(s.key, float(old.value), float(s.value))
		if s.get("kind") == "level" and int(s.level.level) > int(old.get("level", {}).get("level", 0)):
			level_up.emit(s.key, int(s.level.level))
