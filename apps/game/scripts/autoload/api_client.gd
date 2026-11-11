extends Node
## Cliente HTTP del backend de UrbanCraft (AdonisJS).
## Registrado como autoload "Api". Uso:
##     var res := await Api.request_json(HTTPClient.METHOD_GET, "/health")
##     if res.ok: print(res.data)
## La sesión (login con Google, token) la maneja el autoload Auth.

const SETTING_BASE_URL := "urbancraft/network/api_base_url"
const API_PREFIX := "/api/v1"

var base_url: String = ProjectSettings.get_setting(SETTING_BASE_URL, "http://localhost:3333")
## Token de acceso de la sesión. Lo administra el autoload Auth (login, logout,
## persistencia); aquí solo se envía en cada petición.
var token: String = ""


func _ready() -> void:
	# Las peticiones siguen aunque el juego esté en pausa (menú abierto).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Otro backend para pruebas:  godot --path apps/game -- --api-url=http://localhost:3334
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api-url="):
			base_url = arg.substr("--api-url=".length()).trim_suffix("/")


func is_authenticated() -> bool:
	return not token.is_empty()


func health() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/health")


## Hace una petición JSON y devuelve { ok, status, data, error }.
func request_json(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)

	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if is_authenticated():
		headers.append("Authorization: Bearer " + token)

	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": null, "error": "request_failed (%s)" % error_string(err)}

	var result: Array = await http.request_completed
	http.queue_free()

	var request_result: int = result[0]
	var status: int = result[1]
	var raw: PackedByteArray = result[3]

	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": null, "error": "network_error (%d)" % request_result}

	var data: Variant = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
	var ok := status >= 200 and status < 300
	return {"ok": ok, "status": status, "data": data, "error": "" if ok else "http_%d" % status}

