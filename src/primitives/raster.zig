const std = @import("std");
const Vector2 = @import("vector.zig").Vector2;

// todo: There should be better way to do this.
pub fn circleArea(radius: usize) usize {
    if (radius == 0) return 0;

    var result = radius + radius - 1; // Center slice is always fully included.
    for (0..radius) |y| {
        for (0..radius) |x| {
            const dx = radius - x;
            const dy = radius - y;
            if (isPointInsideCircle(
                usize,
                Vector2(usize).zero,
                radius,
                Vector2(usize){ .x = Vector2(usize).zero.x + dx, .y = Vector2(usize).zero.y + dy },
            )) {
                result += (x * 2 + 1) * 2; // Two strips, center always included.
                break;
            }
        }
    }
    return result;
}

pub fn CircleIterator(comptime T: type) type {
    return struct {
        center: Vector2(T),
        radius: usize,
        current: Vector2(T),

        pub fn init(center: Vector2(T), radius: usize) @This() {
            return @This(){
                .center = center,
                .radius = radius,
                .current = center.subtract(Vector2(T).fromScalar(@as(T, @intCast(radius)))),
            };
        }

        pub fn next(self: *@This()) ?Vector2(T) {
            while (self.current.y <= self.center.y + @as(T, @intCast(self.radius))) {
                var point_found = false;
                const point_was = self.current;
                if (isPointInsideCircle(T, self.center, self.radius, self.current))
                    point_found = true;
                self.current.x += 1;
                if (self.current.x > self.center.x + @as(T, @intCast(self.radius))) {
                    self.current.y += 1;
                    self.current.x = self.center.x - @as(T, @intCast(self.radius));
                }
                if (point_found)
                    return point_was;
            }
            return null;
        }
    };
}

pub fn ringArea(inner_radius: usize, outer_radius: usize) usize {
    std.debug.assert(inner_radius <= outer_radius);
    return circleArea(outer_radius) - circleArea(inner_radius);
}

pub fn RingIterator(comptime T: type) type {
    return struct {
        outer_iter: CircleIterator(T),
        inner_radius: usize,

        pub fn init(center: Vector2(T), inner_radius: usize, outer_radius: usize) @This() {
            return @This(){
                .outer_iter = CircleIterator(T).init(center, outer_radius),
                .inner_radius = inner_radius,
            };
        }

        pub fn next(self: *@This()) ?Vector2(T) {
            while (self.outer_iter.next()) |point|
                if (!isPointInsideCircle(T, self.outer_iter.center, self.inner_radius, point))
                    return point;
            return null;
        }
    };
}

// todo: Infer T from center.
// todo: Shouldn't be there, create circle.zig
pub fn isPointInsideCircle(
    comptime T: type,
    center: Vector2(T),
    radius: usize,
    point: Vector2(T),
) bool {
    // todo: This only holds for integral types.
    const diameter = radius + radius - 1;
    return 4 * center.absoluteDifference(point).distanceSquared() <= diameter * diameter;
}

test "point inside circle" {
    try std.testing.expect(!isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32).center.subtract(Vector2(i32).fromScalar(4))));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32).center));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32){ .x = -1, .y = -3 }));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32){ .x = 1, .y = 3 }));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32){ .x = -3, .y = 0 }));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32){ .x = 3, .y = 0 }));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32){ .x = -2, .y = -2 }));
    try std.testing.expect(isPointInsideCircle(i32, Vector2(i32).center, 4, Vector2(i32){ .x = 2, .y = 2 }));

    try std.testing.expect(!isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.subtract(Vector2(u32).fromScalar(4))));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.subtract(Vector2(u32){ .x = 1, .y = 3 })));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.add(Vector2(u32){ .x = 1, .y = 3 })));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.subtract(Vector2(u32){ .x = 3, .y = 0 })));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.add(Vector2(u32){ .x = 3, .y = 0 })));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.subtract(Vector2(u32){ .x = 2, .y = 2 })));
    try std.testing.expect(isPointInsideCircle(u32, Vector2(u32).center, 4, Vector2(u32).center.add(Vector2(u32){ .x = 2, .y = 2 })));
}

test "circle area" {
    try std.testing.expect(circleArea(0) == 0);
    try std.testing.expect(circleArea(1) == 1);
    try std.testing.expect(circleArea(2) == 9);
    try std.testing.expect(circleArea(3) == 21);
    try std.testing.expect(circleArea(4) == 37);
    try std.testing.expect(circleArea(5) == 45);
    try std.testing.expect(circleArea(10) == 141);
}

test "ring area" {
    try std.testing.expect(ringArea(10, 20) == 332);
}
