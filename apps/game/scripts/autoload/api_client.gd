extends Node
## Cliente HTTP del backend de UrbanCraft (AdonisJS).
## Registrado como autoload "Api". Uso:
##     var res := await Api.request_json(HTTPClient.METHOD_GET, "/health")
##     if res.ok: print(res.data)

signal authenticated(user: Dictionary)
signal logged_out

const SETTING_BASE_URL := "urbancraft/network/api_base_url"
const API_PREFIX := "/api/v1"

var base_url: String = ProjectSettings.get_setting(SETTING_BASE_URL, "http://localhost:3333")
var token: String = ""
var current_user: Dictionary = {}


func is_authenticated() -> bool:
	return not token.is_empty()


func health() -> Dictionary:
	return await request_json(HTTPClient.METHOD_GET, "/health")


func signup(full_name: String, email: String, password: String) -> Dictionary:
	var res := await request_json(HTTPClient.METHOD_POST, API_PREFIX + "/auth/signup", {
		"fullName": full_name,
		"email": email,
		"password": password,
		"passwordConfirmation": password,
	})
	_store_session(res)
	return res


func login(email: String, password: String) -> Dictionary:
	var res := await request_json(HTTPClient.METHOD_POST, API_PREFIX + "/auth/login", {
		"email": email,
		"password": password,
	})
	_store_session(res)
	return res


func logout() -> void:
	if is_authenticated():
		await request_json(HTTPClient.METHOD_POST, API_PREFIX + "/account/logout")
	token = ""
	current_user = {}
	logged_out.emit()


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


func _store_session(res: Dictionary) -> void:
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = res.data.get("data", {})
	token = payload.get("token", "")
	current_user = payload.get("user", {})
	if is_authenticated():
		authenticated.emit(current_user)
