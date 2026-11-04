shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.80;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;
uniform float tint : hint_range(0.0, 1.0) = 0.0;
// 异形席的血雾：0 = 关
uniform float blood : hint_range(0.0, 1.0) = 0.0;
// 异形席的夜视：0 = 关，1 = 整屏压成绿磷光
uniform float night_vision : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = distance(uv, vec2(0.5, 0.53));
	float n = fract(sin(dot(uv * vec2(131.7, 271.3) + vec2(TIME * 0.7, TIME * 1.3), vec2(12.9898, 78.233))) * 43758.5453);

	if (night_vision > 0.001) {
		// 夜视：只换亮度、留色相。管子吃进更多光，但红还是红、墙还是墙。
		vec3 src = texture(screen_texture, uv).rgb;
		float lum = dot(src, vec3(0.299, 0.587, 0.114));
		// 暗部抬一点、亮部压下去（软肩）：灯下不爆白，黑处还是黑
		float lifted = clamp(lum * 1.55, 0.0, 1.0);
		lifted = lifted / (1.0 + lifted * 0.62);
		lifted = pow(lifted, 0.88);
		// 色差单独搬过去：不做除法，暗处就不会炸出彩色噪点
		vec3 chroma = (src - vec3(lum)) * 0.75;
		vec3 col = vec3(lifted) + chroma;
		// 薄绿：绿通道抬一点、蓝红各压一点（不是全绿屏）
		col *= vec3(0.84, 1.07, 0.86);
		col = clamp(col, 0.0, 1.0);
		// 一点点跳动的扫描噪点
		col += vec3(0.014, 0.040, 0.018) * (n - 0.5) * 2.0;
		float edge = smoothstep(0.42, 0.99, d) * 0.78;
		col *= (1.0 - edge);
		COLOR = vec4(col, night_vision);
	} else {
		float v = smoothstep(0.42, 0.92, d) * vignette_strength;
		float a = clamp(v + n * grain_strength, 0.0, 0.92);
		vec3 col = mix(vec3(0.0), vec3(0.42, 0.03, 0.03), tint);
		float b = blood * (0.10 + 0.34 * smoothstep(0.10, 0.95, d));
		if (b > a) {
			a = b;
			col = vec3(0.40, 0.02, 0.02);
		}
		COLOR = vec4(col, a);
	}
}
