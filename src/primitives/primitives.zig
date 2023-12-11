pub const vec = @import("vector.zig");
pub const raster = @import("raster.zig");

// todo: Module descriptor function to use in build.zig

pub const Rect = @import("rect-simd.zig").Rect;
pub const Triangle = @import("triangle-simd.zig").Triangle;
pub const GenericVector = vec.GenericVector;
pub const Vector2 = vec.Vector2;
pub const Vector3 = vec.Vector3;
pub const Vector4 = vec.Vector4;

test {
    _ = vec;
    _ = @import("triangle-simd.zig");
    _ = raster;
}
