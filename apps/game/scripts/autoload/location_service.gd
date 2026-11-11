extends Node
## Ubicación real del jugador. Autoload "LocationService".
##
## Al arrancar se resuelve una sola vez (`locate()`), probando en orden:
##   1. Argumentos:  godot --path apps/game -- --lat=40.42 --lon=-3.6887   (exacta)
##   2. GPS del navegador (export web, navigator.geolocation)            (exacta)
##   3. GPS nativo de Android/iOS (TODO: requiere un plugin)               (exacta)
##   4. IP pública, vía backend GET /api/v1/geo/ip              (aproximada, ~ciudad)
##   5. Última ubicación conocida (user://location.cfg)
##   6. Ajustes de proyecto urbancraft/map/default_latitude/longitude
##
## En PC no hay GPS: la posición sale de la IP y puede fallar por varios km.
## Para probar una ubicación concreta usa los argumentos --lat/--lon.
##
## Modo híbrido: esta ubicación es el "ancla". El jugador se mueve libremente
## dentro de un radio (playRadiusMeters del servidor) alrededor de ella.

signal location_changed(latitude: float, longitude: float)
## Se emite cuando `locate()` termina (con la fuente que se usó).
signal located(source: String)

const SETTING_LAT := "urbancraft/map/default_latitude"
const SETTING_LON := "urbancraft/map/default_longitude"
const LAST_LOCATION_PATH := "user://location.cfg"
const BROWSER_TIMEOUT_SECONDS := 15.0

const SOURCE_NAMES := {
	"args": "argumentos",
	"browser": "GPS del navegador",
	"gps": "GPS",
	"ip": "aproximada por IP",
	"last": "última ubicación conocida",
	"default": "ubicación por defecto",
}

var latitude := 0.0
var longitude := 0.0
## "args", "browser", "gps", "ip", "last" o "default".
var source := "default"
## Precisión estimada en metros (-1 = desconocida).
var accuracy_m := -1.0
## Ciudad/país informados por la fuente (solo IP), para mostrar mientras tanto.
var hint_label := ""
var is_located := false

var _locating := false
var _js_callbacks: Array = []  # mantiene vivas las callbacks de JavaScript


func _ready() -> void:
	latitude = ProjectSettings.get_setting(SETTING_LAT, 40.4200)
	longitude = ProjectSettings.get_setting(SETTING_LON, -3.6887)
	# Empieza a ubicar ya, en paralelo con la pantalla inicial.
	locate.call_deferred()


func is_precise() -> bool:
	return source in ["args", "browser", "gps"]


func source_name() -> String:
	return SOURCE_NAMES.get(source, source)


func has_gps() -> bool:
	return false  # TODO: plugin de geolocalización para Android/iOS (ver docs)


## Resuelve la ubicación (una sola vez; llamadas concurrentes esperan la misma).
func locate() -> void:
	if is_located:
		return
	if _locating:
		await located
		return
	_locating = true

	var found := _from_args()
	if not found and OS.has_feature("web"):
		found = await _from_browser()
	if not found:
		found = await _from_ip()
	if not found:
		found = _from_last_known()
	# Si nada funcionó, quedan las coordenadas por defecto (source = "default").

	if source in ["browser", "gps", "ip"]:
		_save_last_known()
	_locating = false
	is_located = true
	located.emit(source)
	location_changed.emit(latitude, longitude)


## Para el plugin de GPS (o pruebas): actualiza la ubicación real.
func set_location(lat: float, lon: float, from_source := "gps", accuracy := -1.0) -> void:
	latitude = clampf(lat, -85.0, 85.0)
	longitude = wrapf(lon, -180.0, 180.0)
	source = from_source
	accuracy_m = accuracy
	if from_source in ["browser", "gps"]:
		_save_last_known()
	location_changed.emit(latitude, longitude)


# --- Fuentes -------------------------------------------------------------------

func _from_args() -> bool:
	var args := _parse_args()
	if not (args.has("lat") and args.has("lon")):
		return false
	_apply(float(args.lat), float(args.lon), "args", 0.0)
	return true


## navigator.geolocation (el navegador pide permiso al jugador).
func _from_browser() -> bool:
	var navigator = JavaScriptBridge.get_interface("navigator")
	if navigator == null or navigator.geolocation == null:
		return false
	var state := {"done": false, "ok": false}
	var on_success := JavaScriptBridge.create_callback(func(args: Array) -> void:
		var coords = args[0].coords
		_apply(float(coords.latitude), float(coords.longitude), "browser", float(coords.accuracy))
		state.ok = true
		state.done = true)
	var on_error := JavaScriptBridge.create_callback(func(_args: Array) -> void:
		state.done = true)
	_js_callbacks = [on_success, on_error]
	var options = JavaScriptBridge.create_object("Object")
	options.enableHighAccuracy = true
	options.timeout = int(BROWSER_TIMEOUT_SECONDS * 1000)
	options.maximumAge = 60000
	navigator.geolocation.getCurrentPosition(on_success, on_error, options)

	var deadline := Time.get_ticks_msec() + int((BROWSER_TIMEOUT_SECONDS + 2.0) * 1000)
	while not state.done and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_js_callbacks.clear()
	return state.ok


## Ubicación aproximada por IP: la resuelve el backend (proveedor intercambiable).
func _from_ip() -> bool:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/geo/ip")
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = res.data
	if not (d.has("latitude") and d.has("longitude")):
		return false
	_apply(float(d.latitude), float(d.longitude), "ip", float(d.get("accuracyKm", 10)) * 1000.0)
	var parts := []
	for key in ["city", "country"]:
		if d.get(key) is String and not str(d[key]).is_empty():
			parts.append(d[key])
	hint_label = ", ".join(parts)
	return true


func _from_last_known() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(LAST_LOCATION_PATH) != OK or not cfg.has_section_key("location", "latitude"):
		return false
	_apply(float(cfg.get_value("location", "latitude")), float(cfg.get_value("location", "longitude")),
		"last", float(cfg.get_value("location", "accuracy_m", -1.0)))
	return true


func _save_last_known() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("location", "latitude", latitude)
	cfg.set_value("location", "longitude", longitude)
	cfg.set_value("location", "accuracy_m", accuracy_m)
	cfg.set_value("location", "source", source)
	cfg.set_value("location", "saved_at", Time.get_unix_time_from_system())
	cfg.save(LAST_LOCATION_PATH)


func _apply(lat: float, lon: float, from_source: String, accuracy: float) -> void:
	latitude = clampf(lat, -85.0, 85.0)
	longitude = wrapf(lon, -180.0, 180.0)
	source = from_source
	accuracy_m = accuracy


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
