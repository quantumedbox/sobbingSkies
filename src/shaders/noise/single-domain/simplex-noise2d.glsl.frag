#version 120

// https://arxiv.org/pdf/1204.1461.pdf

//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : stegu
//     Lastmod : 20110822 (ijm)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
//               https://github.com/stegu/webgl-noise
// 

#define MOD289(p_x) ((p_x) - floor((p_x) * (1.0 / 289.0)) * 289.0)
#define PERMUTE(p_result, p_x) { vec3 _temp = (((p_x) * 34.0) + 10.0) * (p_x); p_result = MOD289(_temp); }

float simplex_noise_2d(in vec2 at) {
  const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                      0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                     -0.577350269189626,  // -1.0 + 2.0 * C.x
                      0.024390243902439); // 1.0 / 41.0
  // First corner
  vec2 i  = floor(at + dot(at, C.yy));
  vec2 x0 = at -   i + dot(i,  C.xx);
  i = MOD289(i); // Avoid truncation effects in permutation

  // i1.x = step( x0.y, x0.x ); // x0.x > x0.y ? 1.0 : 0.0
  // i1.y = 1.0 - i1.x;
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);

  // Other corners
  // x0 = x0 - 0.0 + 0.0 * C.xx ;
  // x1 = x0 - i1 + 1.0 * C.xx ;
  // x2 = x0 - 1.0 + 2.0 * C.xx ;
  vec4 x12 = x0.xyxy + C.xxzz - vec4(i1.xy, 0.0, 0.0);

  // Permutations
  vec3 pp;
  vec3 p = i.y + vec3(0.0, i1.y, 1.0);
  PERMUTE(pp, p);
  pp += i.x + vec3(0.0, i1.x, 1.0);
  PERMUTE(p, pp);
  p = fract(p * C.www);

  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);

  // Gradients: 41 points uniformly over a line, mapped onto a diamond.
  // The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)
  vec3 x = 2.0 * p - 1.0;
  vec3 a0 = x - floor(x + 0.5);
  vec3 h = abs(x) - 0.5;

  m = m * m;
  m = m * m;

  // Normalise gradients implicitly by scaling m
  // Approximation of: m *= inversesqrt( a0*a0 + h*h );
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

  // Compute final noise value at P
  return 130.0 * dot(m, vec3(a0.x * x0.x + h.x * x0.y, a0.yz * x12.xz + h.yz * x12.yw));
}
