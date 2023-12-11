#version 120

// https://en.wikipedia.org/wiki/Perlin_noise

// 4 layers:
// - 0 is currently generated subspace
// - 1 is one to the right
// - 2 is one upper of current
// - 3 is one upper and righter
uniform sampler2D u_values;
uniform sampler2D u_permutations;

// Coordinate that will wrap to point to values of neighboring seed.
#define DOMAIN_LIMIT (64)

float dot_at_grid(in vec2 cell, in vec2 at) {
    bvec2 domain_cross = greaterThanEqual(cell, vec2(DOMAIN_LIMIT, DOMAIN_LIMIT));
    float layer = dot(vec2(domain_cross), vec2(0.25, 0.5));
    float gradient = texture2D(u_values,
        vec2(texture2D(u_permutations, cell * vec2(not(domain_cross)) / DOMAIN_LIMIT).x, layer)).x;
    return dot(vec2(gradient, texture2D(u_values, vec2(abs(gradient), layer)).x), at - cell);
}

// Perlin noise with rescalable grid and continuous separate seed subworlds.
// note: grid_scale should be multiple of 2 and lesser than DOMAIN_LIMIT
// note: Outputs in [-1, 1]
float perlin_noise_2d(in vec2 at, in float grid_scale) {
    vec2 cell = floor(at / grid_scale) * grid_scale;
    vec2 sub = (at - cell) / grid_scale;
    vec2 off = vec2(0.0, grid_scale);
    return mix(mix(dot_at_grid(cell, at), dot_at_grid(cell + off.yx, at), sub.x),
               mix(dot_at_grid(cell + off.xy, at), dot_at_grid(cell + off.yy, at), sub.x), sub.y);
}
