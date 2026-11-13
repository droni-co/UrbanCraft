class_name Atmosphere
extends CanvasLayer
## Etalonaje y luz de la imagen del mundo (va encima del mundo y debajo del HUD).
##
## - Color: más saturación y contraste, luces cálidas y sombras frías (el
##   "look" de ilustración de la referencia en assets/art/baseStyle.jpeg).
## - Nubes: sombras suaves de nubes que pasan despacio sobre el mapa. Están
##   pegadas al mundo (no a la pantalla): se mueven con el viento, no con la cámara.
## - Luz del día: `set_daylight` (lo llama DayNight según la altura del sol)
##   tiñe la imagen (dorado al atardecer, azul de noche).
## - Luces de noche: `set_lights` (postes, el jugador) iluminan su alrededor, y
##   los píxeles amarillo cálido muy claros (ventanas encendidas, que pinta el
##   shader de edificios de noche) no se oscurecen y brillan un poco.
## - Viñeta leve en las esquinas para centrar la mirada.
##
## Todo en un solo shader de pantalla completa; funciona con el renderer
## Compatibility (web y móvil). `enabled = false` lo apaga.

const MAX_LIGHTS := 24

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D clouds : repeat_enable, filter_linear;

uniform float saturation = 1.16;
uniform float contrast = 1.07;
uniform float brightness = 1.02;
uniform vec3 shadow_tint : source_color = vec3(0.93, 0.97, 1.08);
uniform vec3 light_tint : source_color = vec3(1.06, 1.01, 0.92);
uniform float vignette = 0.22;

// Nubes: cuánto oscurecen, tamaño (px de mundo por repetición) y posición.
uniform float cloud_strength = 0.16;
uniform float cloud_scale = 1400.0;
// Mundo visible: esquina superior izquierda y tamaño (px de mundo).
uniform vec2 view_origin = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec2 wind = vec2(9.0, 4.0);

// Luz del día: color que multiplica la escena y cuánto es de noche (0-1).
uniform vec3 ambient = vec3(1.0);
uniform float night = 0.0;
// Luces: xy = posición en el mundo, z = radio (px de mundo), w = intensidad.
uniform vec4 lights[24];  // MAX_LIGHTS
uniform int light_count = 0;
uniform vec3 light_color : source_color = vec3(1.0, 0.78, 0.45);

float emissive(vec3 c) {
	// Amarillo cálido muy claro: ventanas encendidas y bombillas.
	return smoothstep(0.82, 0.95, c.r) * smoothstep(0.62, 0.78, c.g) * (1.0 - smoothstep(0.45, 0.62, c.b));
}

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	vec2 world = view_origin + SCREEN_UV * view_size;

	float n = texture(clouds, (world - wind * TIME) / cloud_scale).r;
	float shade = smoothstep(0.48, 0.72, n) * cloud_strength * (1.0 - night);
	c *= 1.0 - shade;

	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, saturation * (1.0 - 0.35 * night));
	c = (c - 0.5) * contrast + 0.5;
	c *= mix(shadow_tint, light_tint, smoothstep(0.15, 0.85, lum)) * brightness;

	// Luz: la del día más la de las lámparas cercanas.
	vec3 light = ambient;
	for (int i = 0; i < light_count; i++) {
		vec4 l = lights[i];
		vec2 d = (world - l.xy) * vec2(1.0, 2.0);  // pozo de luz aplastado como el suelo
		float f = 1.0 - smoothstep(0.0, l.z, length(d));
		light += light_color * f * f * l.w * night;
	}
	vec3 lit = c * light;
	// Las ventanas encendidas no se apagan con la noche y dejan un halo.
	if (night > 0.0) {
		float e = emissive(c);
		vec2 px = 1.0 / vec2(textureSize(screen_texture, 0));
		float halo = 0.0;
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.785398;
			halo += emissive(texture(screen_texture, SCREEN_UV + vec2(cos(a), sin(a)) * px * 5.0).rgb);
		}
		lit = mix(lit, c * 1.05, e * night);
		lit += light_color * halo / 8.0 * 0.35 * night;
	}
	c = lit;

	vec2 v = SCREEN_UV - 0.5;
	c *= 1.0 - (vignette + 0.18 * night) * smoothstep(0.25, 0.75, dot(v, v) * 2.0);

	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

@export var camera: Camera2D
@export var enabled := true:
	set(value):
		enabled = value
		if _rect:
			_rect.visible = value

var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = 5
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise

	_material = ShaderMaterial.new()
	_material.shader = Shader.new()
	_material.shader.code = SHADER
	_material.set_shader_parameter("clouds", texture)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = enabled
	add_child(_rect)


## Color de la luz del día (multiplica la escena) y cuánto es de noche (0-1).
func set_daylight(ambient: Color, night: float) -> void:
	_material.set_shader_parameter("ambient", Vector3(ambient.r, ambient.g, ambient.b))
	_material.set_shader_parameter("night", night)


## Luces puntuales: [Vector4(x, y, radio, intensidad)] en coordenadas del mundo.
func set_lights(lights: Array[Vector4]) -> void:
	var count := mini(lights.size(), MAX_LIGHTS)
	var packed := PackedVector4Array()
	packed.resize(MAX_LIGHTS)
	for i in count:
		packed[i] = lights[i]
	_material.set_shader_parameter("lights", packed)
	_material.set_shader_parameter("light_count", count)


## Rectángulo de mundo que se ve en pantalla.
func view_rect() -> Rect2:
	if camera == null:
		return Rect2()
	var to_world := camera.get_canvas_transform().affine_inverse()
	var origin := to_world * Vector2.ZERO
	return Rect2(origin, to_world * camera.get_viewport_rect().size - origin)


func _process(_delta: float) -> void:
	if not enabled or camera == null:
		return
	# Para pegar las nubes y las luces al mapa.
	var view := view_rect()
	_material.set_shader_parameter("view_origin", view.position)
	_material.set_shader_parameter("view_size", view.size)
