shader_type spatial;
render_mode specular_disabled;

uniform vec4 grass_dark : source_color = vec4(0.31, 0.39, 0.12, 1.0);
uniform vec4 grass_light : source_color = vec4(0.38, 0.44, 0.16, 1.0);

varying vec3 world_position;
varying float local_height;

float hash_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float ground_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(point));
	float lower = mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x);
	float upper = mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), blend.x);
	return mix(lower, upper, blend.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_height = VERTEX.y;
}

void fragment() {
	vec3 face_normal = normalize(cross(dFdx(world_position), dFdy(world_position)));
	if (face_normal.y < 0.0) {
		face_normal = -face_normal;
	}
	float grass_cover = smoothstep(0.85, 0.97, face_normal.y) * smoothstep(-0.18, -0.04, local_height);
	float variation = mix(ground_noise(world_position.xz * 0.55), ground_noise(world_position.xz * 1.7), 0.25);
	ALBEDO = mix(COLOR.rgb, mix(grass_dark.rgb, grass_light.rgb, variation), grass_cover);
	NORMAL = normalize(mix(NORMAL, mat3(VIEW_MATRIX) * face_normal, grass_cover));
	ROUGHNESS = 0.95;
}
