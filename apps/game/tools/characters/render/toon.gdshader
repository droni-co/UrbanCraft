shader_type spatial;
render_mode diffuse_toon, specular_disabled, ambient_light_disabled;
// Sombreado "pintado": la textura de Meshy casi plana, con un tono de sombra
// cálido y suave (sin brillos ni oclusión), como el arte del juego.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.52, 0.55);
uniform float saturation = 1.08;
uniform float brightness = 1.0;

varying vec3 base;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.15, 0.25, ndl) * ATTENUATION;
	vec3 shade = mix(shadow_tint, vec3(1.0), lit);
	DIFFUSE_LIGHT += shade * LIGHT_COLOR * brightness;
}
