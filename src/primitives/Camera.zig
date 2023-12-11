const std = @import("std");
const zmath = @import("zmath");

position: zmath.f32x4,
direction: zmath.f32x4,
up: zmath.f32x4 = zmath.f32x4(0.0, 1.0, 0.0, 0.0),
fov: f32 = std.math.pi / 2.0,
aspect_ratio: f32,
near_plane: f32 = 0.1,
far_plane: f32,

// todo: We can eliminate need for swizzling when multiplying if we make rotate `.looAtRh()` matrix on construction.
pub fn calculateObjectToClipMatrix(self: @This()) zmath.Mat {
    const world_to_view = zmath.lookAtRh(self.position, self.position + self.direction, self.up);
    const view_to_clip = zmath.perspectiveFovRhGl(self.fov, self.aspect_ratio, self.near_plane, self.far_plane);
    return zmath.mul(world_to_view, view_to_clip);
}
