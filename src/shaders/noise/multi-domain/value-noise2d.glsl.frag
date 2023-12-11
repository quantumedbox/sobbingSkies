#version 120

// https://gmshaders.com/tutorials/tips_and_tricks/

// 4 layers:
// - 0 is currently generated subspace
// - 1 is one to the right
// - 2 is one upper of current
// - 3 is one upper and righter
uniform sampler2D u_values;

vec2 hash(in vec2 p) {
    p = mod(p, 7.31);
    return vec2(fract(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453), 0.0);
}

// note: Outputs in [0, 1]
float value_noise_2d(in vec2 at) {
    vec2 cell = floor(at);
    vec2 sub = at - cell;
    // sub *= sub*(3. - 2. * sub);
    const vec2 off = vec2(0.0, 1.0);

    return mix(mix(texture2D(u_values, hash(cell + off.xx)).x, texture2D(u_values, hash(cell + off.yx)).x, sub.x),
               mix(texture2D(u_values, hash(cell + off.xy)).x, texture2D(u_values, hash(cell + off.yy)).x, sub.x), sub.y);
}
