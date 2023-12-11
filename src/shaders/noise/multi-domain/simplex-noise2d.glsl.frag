#version 120

// https://procedural-content-generation.fandom.com/wiki/Simplex_Noise

// 4 layers:
// - 0 is currently generated subspace
// - 1 is one to the right
// - 2 is one upper of current
// - 3 is one upper and righter
uniform sampler2D u_values;

// Coordinate that will wrap to point to values of neighboring seed.
#define UNIT_LIMIT (64)

// todo: Test whether this hashing is sufficient. It would be better to have one
//       without need for normalization.
vec2 value_offset(in vec2 at) {
    at = mod(at, 7.31);
    return vec2(0.5 + 0.5 * fract(sin(at.x * 12.9898 + at.y * 78.233) * 43758.5453), 0.0);
}

float dot_at_grid(in vec2 cell, in vec2 at) {
    // todo: Change to a single texture lookup.
    vec2 gradient = vec2(texture2D(u_values, value_offset(cell)).x, texture2D(u_values, value_offset(cell + 29.0)).x);
    return dot(gradient, at);
}

// note: Outputs in [-1, 1]
float simplex_noise_2d(in vec2 at, in float grid_scale) {
    const vec3 C = vec3(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                        0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                       -0.577350269189626); // -1.0 + 2.0 * C.x
    vec2 i = floor(at + dot(at, C.yy));
    vec2 x0 = at - (i - dot(i,  C.xx)); // First corner
    vec2 d = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz - vec4(d.xy, 0.0, 0.0); // Other two corners

    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    m *= vec3(dot_at_grid(i, x0), dot_at_grid(i + d, x12.xy), dot_at_grid(i + 1.0, x12.zw));

    return 70.0 * (m.x + m.y + m.z);
}

 // float snoise(const in vec2 P) {

 // // Skew and unskew factors are a bit hairy for 2D, so define them as constants
 // // This is (sqrt(3.0)-1.0)/2.0
 // #define F2 0.366025403784
 // // This is (3.0-sqrt(3.0))/6.0
 // #define G2 0.211324865405

 //  // Skew the (x,y) space to determine which cell of 2 simplices we're in
 //   float s = (P.x + P.y) * F2;  // Hairy factor for 2D skewing
 //  vec2 Pi = floor(P + s);
 //  float t = (Pi.x + Pi.y) * G2; // Hairy factor for unskewing
 //  vec2 P0 = Pi - t; // Unskew the cell origin back to (x,y) space
 //  Pi = Pi * ONE + ONEHALF; // Integer part, scaled and offset for texture lookup

 //  vec2 Pf0 = P - P0; // The x,y distances from the cell origin

 //  // For the 2D case, the simplex shape is an equilateral triangle.
 //  // Find out whether we are above or below the x=y diagonal to
 //  // determine which of the two triangles we're in.
 //  vec2 o1;
 //  if(Pf0.x > Pf0.y) o1 = vec2(1.0, 0.0); // +x, +y traversal order
 //  else o1 = vec2(0.0, 1.0);        // +y, +x traversal order

 //  // Noise contribution from simplex origin
 //  vec2 grad0 = texture2D(permTexture, Pi).rg * 4.0 - 1.0;
 //  float t0 = 0.5 - dot(Pf0, Pf0);
 //  float n0;
 //  if (t0 < 0.0) n0 = 0.0;
 //  else {
 //   t0 *= t0;
 //   n0 = t0 * t0 * dot(grad0, Pf0);
 //  }

 //  // Noise contribution from middle corner
 //  vec2 Pf1 = Pf0 - o1 + G2;
 //  vec2 grad1 = texture2D(permTexture, Pi + o1*ONE).rg * 4.0 - 1.0;
 //  float t1 = 0.5 - dot(Pf1, Pf1);
 //  float n1;
 //  if (t1 < 0.0) n1 = 0.0;
 //  else {
 //   t1 *= t1;
 //   n1 = t1 * t1 * dot(grad1, Pf1);
 //  }

 //  // Noise contribution from last corner
 //  vec2 Pf2 = Pf0 - vec2(1.0-2.0*G2);
 //  vec2 grad2 = texture2D(permTexture, Pi + vec2(ONE, ONE)).rg * 4.0 - 1.0;
 //  float t2 = 0.5 - dot(Pf2, Pf2);
 //  float n2;
 //  if(t2 < 0.0) n2 = 0.0;
 //  else {
 //   t2 *= t2;
 //   n2 = t2 * t2 * dot(grad2, Pf2);
 //  }

 //  // Sum up and scale the result to cover the range [-1,1]
 //  return 70.0 * (n0 + n1 + n2);
 // }
