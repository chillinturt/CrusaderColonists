// Map scenery under the fog of war: darkened where you have never looked,
// dimmed where you have looked but can't see now, normal where you can see.
// fog_tex is one texel per nav cell (white = visible, grey = explored, black = unexplored).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 emission : source_color = vec3(0.0);
uniform float roughness = 0.9;
// Terrain: colors come from the mesh (authored in sRGB).
uniform bool use_vertex_color = false;
uniform sampler2D fog_tex : filter_linear, repeat_disable, hint_default_white;
// xy = world XZ of the texture's corner, zw = 1 / world size it spans.
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float fog_light(vec3 p) {
	// A small blur on top of the linear filtering, so the edge of sight is soft
	// instead of following the 2 m grid.
	vec2 uv = (p.xz - fog_rect.xy) * fog_rect.zw;
	vec2 t = 0.8 / vec2(textureSize(fog_tex, 0));
	float v = texture(fog_tex, uv).r * 4.0;
	v += (texture(fog_tex, uv + vec2(t.x, 0.0)).r + texture(fog_tex, uv - vec2(t.x, 0.0)).r
		+ texture(fog_tex, uv + vec2(0.0, t.y)).r + texture(fog_tex, uv - vec2(0.0, t.y)).r) * 2.0;
	v += texture(fog_tex, uv + t).r + texture(fog_tex, uv - t).r
		+ texture(fog_tex, uv + vec2(t.x, -t.y)).r + texture(fog_tex, uv + vec2(-t.x, t.y)).r;
	v /= 16.0;
	return v < 0.5 ? mix(0.06, 0.4, v * 2.0) : mix(0.4, 1.0, (v - 0.5) * 2.0);
}

void fragment() {
	vec3 c = albedo;
	if (use_vertex_color) {
		vec3 s = COLOR.rgb;
		c = mix(pow((s + vec3(0.055)) / 1.055, vec3(2.4)), s / 12.92, lessThan(s, vec3(0.04045)));
	}
	float light = fog_light(world_pos);
	ALBEDO = c * light;
	EMISSION = emission * light;
	ROUGHNESS = roughness;
	// Sky light and reflections would otherwise keep hidden ground bright.
	AO = light;
	AO_LIGHT_AFFECT = 1.0 - light;
	SPECULAR = 0.5 * light;
}
