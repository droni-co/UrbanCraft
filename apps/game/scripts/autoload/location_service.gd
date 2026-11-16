extends Node
## Ubicación real del jugador. Autoload "LocationService".
##
## Al arrancar se resuelve una sola vez (`locate()`), probando en orden:
##   1. Argumentos:  godot --path apps/game -- --lat=40.42 --lon=-3.6887   (exacta)
##   2. GPS del navegador (export web, navigator.geolocation)            (exacta)
##   3. GPS nativo de Android (LocationManager vía JavaClassWrapper)       (exacta)
##   4. IP pública, vía backend GET /api/v1/geo/ip              (aproximada, ~ciudad)
##   5. Última ubicación conocida (user://location.cfg)
##   6. Ajustes de proyecto urbancraft/map/default_latitude/longitude
##
## En PC no hay GPS: la posición sale de la IP y puede fallar por varios km.
## Para probar una ubicación concreta usa los argumentos --lat/--lon.
##
## Modo híbrido: esta ubicación es el "ancla". El jugador se mueve libremente
## dentro de un radio (playRadiusMeters del servidor) alrededor de ella.
##
## Teletransporte (menú del jugador): `teleport()` mueve el ancla a otras
## coordenadas y guarda la ubicación real para `return_home()`. No se guarda
## entre sesiones: al reiniciar el juego vuelves a tu ubicación real.
## TODO(multijugador): el servidor debe autorizar los teletransportes.

signal location_changed(latitude: float, longitude: float)
## Se emite cuando `locate()` termina (con la fuente que se usó).
signal located(source: String)

const SETTING_LAT := "urbancraft/map/default_latitude"
const SETTING_LON := "urbancraft/map/default_longitude"
const LAST_LOCATION_PATH := "user://location.cfg"
const BROWSER_TIMEOUT_SECONDS := 15.0
## Android: tiempo máximo esperando el primer dato del GPS, y precisión con la
## que ya no vale la pena seguir esperando una mejor.
const GPS_TIMEOUT_SECONDS := 20.0
const GPS_GOOD_ACCURACY_M := 40.0
## Una última ubicación conocida del sistema sirve si tiene menos de esto.
const GPS_LAST_KNOWN_MAX_AGE_S := 120.0
const PERMISSION_TIMEOUT_SECONDS := 60.0
const FINE_LOCATION := "android.permission.ACCESS_FINE_LOCATION"
const COARSE_LOCATION := "android.permission.ACCESS_COARSE_LOCATION"

const SOURCE_NAMES := {
	"args": "argumentos",
	"browser": "GPS del navegador",
	"gps": "GPS",
	"ip": "aproximada por IP",
	"last": "última ubicación conocida",
	"default": "ubicación por defecto",
	"teleport": "teletransporte",
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

## Ubicación real guardada mientras el jugador está teletransportado.
var _home := {}

var _locating := false
var _js_callbacks: Array = []  # mantiene vivas las callbacks de JavaScript
## Android: mejor dato recibido del GPS mientras se espera ({lat, lon, accuracy}).
var _gps_best := {}
var _gps_listener: JavaObject = null


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
	return OS.has_feature("android")


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
	if not found and OS.has_feature("android"):
		found = await _from_android_gps()
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


## Mueve el ancla de la zona de juego a otras coordenadas. El mundo debe
## recargarse después (World lo hace) para generar la zona nueva.
func teleport(lat: float, lon: float) -> void:
	if not is_teleported():
		_home = {"latitude": latitude, "longitude": longitude, "source": source,
			"accuracy_m": accuracy_m, "hint_label": hint_label}
	_apply(lat, lon, "teleport", 0.0)
	hint_label = ""
	location_changed.emit(latitude, longitude)


## Vuelve a la ubicación real que había antes del primer teletransporte.
func return_home() -> void:
	if not is_teleported():
		return
	_apply(_home.latitude, _home.longitude, _home.source, _home.accuracy_m)
	hint_label = _home.hint_label
	_home = {}
	location_changed.emit(latitude, longitude)


func is_teleported() -> bool:
	return not _home.is_empty()


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


## GPS de Android: pide el permiso de ubicación y escucha el LocationManager
## (proveedores gps y network) hasta tener un dato preciso o agotar el tiempo.
func _from_android_gps() -> bool:
	if not await _request_location_permission():
		push_warning("[Location] Permiso de ubicación denegado; se usa la IP.")
		return false
	var runtime = Engine.get_singleton("AndroidRuntime") if Engine.has_singleton("AndroidRuntime") else null
	if runtime == null:
		return false
	var context = runtime.getApplicationContext()
	var manager = context.getSystemService("location") if context != null else null
	if manager == null:
		return false

	var providers: Array[String] = []
	for provider in ["gps", "network"]:
		if manager.isProviderEnabled(provider):
			providers.append(provider)
	if providers.is_empty():
		push_warning("[Location] La ubicación del teléfono está apagada; se usa la IP.")
		return false

	_gps_best = {}
	# Dato reciente que el sistema ya tenga: sirve de inmediato si es preciso.
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for provider in providers:
		var last = manager.getLastKnownLocation(provider)
		if last != null and now_ms - float(last.getTime()) <= GPS_LAST_KNOWN_MAX_AGE_S * 1000.0:
			_on_gps_fix(float(last.getLatitude()), float(last.getLongitude()), float(last.getAccuracy()))

	if _gps_best.is_empty() or _gps_best.accuracy > GPS_GOOD_ACCURACY_M:
		var looper = JavaClassWrapper.wrap("android.os.Looper").getMainLooper()
		_gps_listener = JavaClassWrapper.create_proxy(self, PackedStringArray(["android.location.LocationListener"]))
		for provider in providers:
			manager.requestLocationUpdates(provider, 1000, 0.0, _gps_listener, looper)
		var deadline := Time.get_ticks_msec() + int(GPS_TIMEOUT_SECONDS * 1000)
		while Time.get_ticks_msec() < deadline:
			if not _gps_best.is_empty() and _gps_best.accuracy <= GPS_GOOD_ACCURACY_M:
				break
			await get_tree().process_frame
		manager.removeUpdates(_gps_listener)
		_gps_listener = null

	if _gps_best.is_empty():
		return false
	_apply(_gps_best.lat, _gps_best.lon, "gps", _gps_best.accuracy)
	return true


## LocationListener (lo llama Android desde su hilo principal).
func onLocationChanged(location) -> void:
	if location == null:
		return
	_on_gps_fix.call_deferred(float(location.getLatitude()), float(location.getLongitude()),
		float(location.getAccuracy()))


func onProviderEnabled(_provider) -> void:
	pass


func onProviderDisabled(_provider) -> void:
	pass


func onStatusChanged(_provider, _status, _extras) -> void:
	pass


func _on_gps_fix(lat: float, lon: float, accuracy: float) -> void:
	if accuracy <= 0.0:
		accuracy = 9999.0
	if _gps_best.is_empty() or accuracy < _gps_best.accuracy:
		_gps_best = {"lat": lat, "lon": lon, "accuracy": accuracy}


## Pide el permiso de ubicación (el sistema muestra el diálogo la primera vez).
func _request_location_permission() -> bool:
	if _has_location_permission():
		return true
	var state := {"done": false}
	var on_result := func(_permission: String, _granted: bool) -> void:
		state.done = true
	get_tree().on_request_permissions_result.connect(on_result)
	if OS.request_permission(FINE_LOCATION):
		state.done = true
	var deadline := Time.get_ticks_msec() + int(PERMISSION_TIMEOUT_SECONDS * 1000)
	while not state.done and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	get_tree().on_request_permissions_result.disconnect(on_result)
	return _has_location_permission()


func _has_location_permission() -> bool:
	var granted := OS.get_granted_permissions()
	return FINE_LOCATION in granted or COARSE_LOCATION in granted


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
