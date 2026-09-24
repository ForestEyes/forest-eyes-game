shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float curvature : hint_range(-1.0, 1.0) = 0.5; // Intensidade do efeito esférico (0 = plano, 1 = globo)

void fragment() {
    // 1. Obtém a proporção real da tela (Aspect Ratio)
    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
    float aspect = screen_size.x / screen_size.y;
    
    // 2. Centraliza as coordenadas UV [-0.5, 0.5]
    vec2 st = SCREEN_UV - vec2(0.5);
    
    // Corrige a largura para que a distorção seja um círculo perfeito e não um ovo
    st.x *= aspect;
    
    // Distância atual do centro
    float r = length(st);
    
    // Raio do círculo que circunscreve a tela (distância do centro até o canto)
    float r_max = length(vec2(0.5 * aspect, 0.5));
    
    // Normaliza a distância de 0.0 (centro) a 1.0 (cantos da tela)
    float r_norm = r / r_max;
    
    // 3. Deformação esférica (curva a malha projetando o plano sobre uma esfera)
    // Usamos seno para inflar o centro e comprimir suavemente em direção às bordas
    float sphere_r = sin(r_norm * 1.57079632679); // 1.570796 = PI / 2
    float r_distorted = mix(r_norm, sphere_r, curvature);
    
    // Aplica o fator de escala mantendo a simetria radial
    vec2 st_distorted = st * (r_distorted / max(r_norm, 0.0001));
    
    // Desfaz a correção de aspecto
    st_distorted.x /= aspect;
    
    // Retorna para coordenadas UV da tela [0.0, 1.0]
    vec2 final_uv = st_distorted + vec2(0.5);
    
    COLOR = texture(screen_texture, final_uv);
}