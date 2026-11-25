// Хроматическая аберрация (шаг 11.10, PostFx): красный и синий каналы расходятся от центра экрана.
// Узел виден только доли секунды после удара на малом здоровье — копия экрана нужна лишь тогда.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amount = 0.0;

void fragment() {
	vec2 offset = (SCREEN_UV - vec2(0.5)) * amount;
	float r = texture(screen, SCREEN_UV + offset).r;
	float g = texture(screen, SCREEN_UV).g;
	float b = texture(screen, SCREEN_UV - offset).b;
	COLOR = vec4(r, g, b, 1.0);
}
