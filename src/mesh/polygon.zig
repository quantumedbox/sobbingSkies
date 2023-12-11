const std = @import("std");

pub const Vector2 = @import("primitives").Vector2;

// https://stackoverflow.com/questions/1165647/how-to-determine-if-a-list-of-polygon-points-are-in-clockwise-order

pub const Orientation = enum { clockwise, counter_clockwise };

// todo: Generalize to higher dimensions.
/// Cartesian with mirrored Y is assumed.
pub fn determineOrientation(T: type, polygon: []const Vector2(T)) Orientation {
    var sum: usize = 0;
    for (0..polygon.len) |i| {
        const a = polygon[i];
        const b = polygon[(i + 1) % polygon.len];
        sum += (b.x() - a.x()) * (b.y() + a.y());
    }

    return if (sum < 0) .clockwise else .counter_clockwise;
}

test "determineOrientation" {
    try std.testing.expect(determineOrientation(f32, &[_]Vector2(f32){
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 1, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
    }) == .clockwise);

    try std.testing.expect(determineOrientation(f32, &[_]Vector2(f32){
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
        Vector2(f32).init(.{ 1, 0 }),
    }) == .counter_clockwise);
}
