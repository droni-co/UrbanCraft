extends Node
## Cliente HTTP del backend de UrbanCraft (AdonisJS).
## Registrado como autoload "Api". Uso:
##     var res := await Api.request_json(HTTPClient.METHOD_GET, "/health")
##     if res.ok: print(res.data)
## La sesión (login con Google, token) la maneja el autoload Auth.

const SETTING_BASE_URL := "urbancraft/network/api_base_url"
const API_PREFIX := "/api/v1"
const CLOUD_URL := "https://urbancraft.droni.vip"
const LOCAL_URL := "http://localhost:3333"
## Variable de entorno para elegir backend (útil al ejecutar desde el editor).
const ENV_API_URL := "URBANCRAFT_API_URL"

## Por defecto, el servidor en la nube. Ver _resolve_base_url() para cambiarlo.
var base_url: String = _resolve_base_url()
## Token de acceso de la sesión. Lo administra el autoload Auth (login, logout,
## persistencia); aquí solo se envía en cada petición.
var token: String = ""


func _ready() -> void:
	# Las peticiones siguen aunque el juego esté en pausa (menú abierto).
	process_mode = Node.PROCESS_MODE_ALWAYS
	if base_url != CLOUD_URL:
		print("[Api] Backend: %s" % base_url)


## Backend a usar, de mayor a menor prioridad:
##   1. `-- --api-url=http://host:puerto`  (cualquier backend)
##   2. `-- --local`                       (http://localhost:3333)
##   3. variable de entorno URBANCRAFT_API_URL (`local` equivale a LOCAL_URL)
##   4. ajuste urbancraft/network/api_base_url (por defecto la nube)
static func _resolve_base_url() -> String:
	var url := ""
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--api-url="):
			url = arg.substr("--api-url=".length())
	if url.is_empty() and "--local" in args:
		url = LOCAL_URL
	if url.is_empty():
		url = OS.get_environment(ENV_API_URL)
		if url == "local":
			url = LOCAL_URL
	if url.is_empty():
		url = str(ProjectSettings.get_setting(SETTING_BASE_URL, CLOUD_URL))
	return url.strip_edges().trim_suffix("/")


func is_cloud() -> bool:
	return base_url == CLOUD_URL


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

