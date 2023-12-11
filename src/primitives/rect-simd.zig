const std = @import("std");
const Vector2 = @import("vector.zig").Vector2;

// todo: `unlikely` variant of this api with early rejection, without simd.
// todo: Don't assume two dimensions.
// todo: Implement over vector.

pub fn Rect(comptime T: type) type {
    return struct {
        // note: Upper-left origin is assumed, if second point lies left or up of first it willn't work.
        xyxy: @Vector(4, T),

        pub fn init(upperleft: Vector2(T), bottomright: Vector2(T)) @This() {
            std.debug.assert(upperleft.x() <= bottomright.x());
            std.debug.assert(upperleft.y() <= bottomright.y());
            return .{
                .xyxy = [4]T{ upperleft.x(), upperleft.y(), bottomright.x(), bottomright.y() },
            };
        }

        // todo: Return vector or vectors?
        /// Order: Upperleft, upperright, bottomleft, bottomright.
        pub fn corners(self: @This()) [4]Vector2(T) {
            return [4]Vector2(T){
                Vector2(T).init(.{ self.xyxy[0], self.xyxy[1] }),
                Vector2(T).init(.{ self.xyxy[2], self.xyxy[1] }),
                Vector2(T).init(.{ self.xyxy[0], self.xyxy[3] }),
                Vector2(T).init(.{ self.xyxy[2], self.xyxy[3] }),
            };
        }

        pub fn isPointWithin(self: @This(), p: @Vector(2, T)) bool {
            const q = @shuffle(T, p, self.xyxy, [4]i32{ -1, -2, 0, 1 });
            const w = @shuffle(T, p, self.xyxy, [4]i32{ 0, 1, -3, -4 });
            return @reduce(.And, q <= w);
        }

        pub fn isRectWithin(self: @This(), a: @This()) bool {
            const q = @shuffle(T, a.xyxy, self.xyxy, [8]i32{ 0, 1, 2, 3, -1, -2, -1, -2 });
            const w = @shuffle(T, a.xyxy, self.xyxy, [8]i32{ -3, -4, -3, -4, 0, 1, 2, 3 });
            return @reduce(.And, q <= w);
        }

        // todo: Handle zero area cases?
        pub fn isRectIntersecting(self: @This(), a: @This()) bool {
            const q = @shuffle(T, a.xyxy, self.xyxy, [4]i32{ 0, 1, -1, -2 });
            const w = @shuffle(T, a.xyxy, self.xyxy, [4]i32{ -3, -4, 2, 3 });
            return @reduce(.And, q <= w);
        }

        // pub const PointRelation = enum(u4) {
        //     inside = 0b0000,
        //     toleft = 0b0001,
        //     above = 0b0010,
        //     above_toleft = 0b0011,
        //     toright = 0b0100,
        //     above_toright = 0b0110,
        //     below = 0b1000,
        //     below_toleft = 0b1001,
        //     below_toright = 0b1100,
        //
        //     pub const Vector = @Vector(4, bool);
        // };

        // pub fn pointRelation(self: @This(), p: @Vector(2, T)) PointRelation.Vector {
        //     const r0 = p < @shuffle(T, self.xyxy, undefined, [2]i32{ 0, 1 });
        //     const r1 = p > @shuffle(T, self.xyxy, undefined, [2]i32{ 2, 3 });
        //     return @shuffle(bool, r0, r1, [4]i32{ 0, 1, -1, -2 });
        // }

        // https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
        pub fn isLineIntersecting(self: @This(), l: @Vector(4, T)) bool {
            const r0 = l < @shuffle(T, self.xyxy, undefined, [4]i32{ 0, 1, 0, 1 });
            const r1 = l > @shuffle(T, self.xyxy, undefined, [4]i32{ 2, 3, 2, 3 });
            const a = @shuffle(bool, r0, r1, [4]i32{ 0, 1, -1, -2 });
            const b = @shuffle(bool, r0, r1, [4]i32{ 2, 3, -3, -4 });
            return !@reduce(.Or, @select(bool, a, b, a));
        }

        // todo: bitand and or could be performed on 8 and 4 elements separately, combining the resuts.
        //       Compiler does an awful job at this, so, handwritten assembly seems to be required.
        pub fn isTriangleIntersecting(self: @This(), t: @Vector(6, T)) bool {
            const r0 = t < @shuffle(T, self.xyxy, undefined, [6]i32{ 0, 1, 0, 1, 0, 1 });
            const r1 = t > @shuffle(T, self.xyxy, undefined, [6]i32{ 2, 3, 2, 3, 2, 3 });
            const a = @shuffle(bool, r0, r1, [12]i32{ 0, 1, 0, 1, -1, -2, -1, -2, 2, 3, -3, -4 });
            const b = @shuffle(bool, r0, r1, [12]i32{ 2, 3, 4, 5, -3, -4, -5, -6, 4, 5, -5, -6 });
            return !@reduce(.Or, @select(bool, a, b, a));
        }
    };
}

test "within" {
    const rect = Rect(f32){ .xyxy = .{ 0, 0, 1, 1 } };

    try std.testing.expect(rect.isPointWithin(@Vector(2, f32){ 0.5, 0.5 }));
    try std.testing.expect(!rect.isPointWithin(@Vector(2, f32){ -0.5, -0.5 }));
    try std.testing.expect(!rect.isPointWithin(@Vector(2, f32){ -0.5, 1.5 }));
    try std.testing.expect(!rect.isPointWithin(@Vector(2, f32){ 1.5, 1.5 }));
    try std.testing.expect(!rect.isPointWithin(@Vector(2, f32){ 1.5, -0.5 }));

    try std.testing.expect(rect.isRectWithin(Rect(f32){ .xyxy = .{ 0.25, 0.25, 0.75, 0.75 } }));
    try std.testing.expect(rect.isRectWithin(Rect(f32){ .xyxy = .{ 0, 0, 1, 1 } }));
    try std.testing.expect(!rect.isRectWithin(Rect(f32){ .xyxy = .{ -0.25, 0.25, 0.75, 0.75 } }));
}

test "intersection" {
    const rect = Rect(f32){ .xyxy = .{ 0, 0, 1, 1 } };

    try std.testing.expect(rect.isRectIntersecting(Rect(f32){ .xyxy = .{ 0.25, 0.25, 0.75, 0.75 } }));
    try std.testing.expect(rect.isRectIntersecting(Rect(f32){ .xyxy = .{ 0, 0, 1, 1 } }));
    try std.testing.expect(rect.isRectIntersecting(Rect(f32){ .xyxy = .{ -0.25, 0.25, 0.75, 0.75 } }));
    try std.testing.expect(!rect.isRectIntersecting(Rect(f32){ .xyxy = .{ 1.25, 1.25, 2, 2 } }));
    try std.testing.expect(!rect.isRectIntersecting(Rect(f32){ .xyxy = .{ -0.25, -0.25, -0.1, -0.1 } }));

    try std.testing.expect(!rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, -0.75, -0.75 }));
    try std.testing.expect(!rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, 0.75, -0.75 }));
    try std.testing.expect(!rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, 1.5, -0.75 }));
    try std.testing.expect(!rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, -0.5, 0.5 }));
    try std.testing.expect(rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, 0.5, 0.5 }));
    try std.testing.expect(rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, 0.5, 1.5 }));
    try std.testing.expect(!rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, -0.5, 1.5 }));
    try std.testing.expect(rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, 0.5, 1.5 }));
    try std.testing.expect(rect.isLineIntersecting(@Vector(4, f32){ -0.25, -0.25, 1.5, 1.5 }));
}
