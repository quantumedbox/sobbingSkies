const std = @import("std");

const Vector2 = @import("vector.zig").Vector2;
const Vector3 = @import("vector.zig").Vector3;

// todo: Don't assume two dimensions.

// todo: https://en.wikipedia.org/wiki/Area_of_a_triangle

pub fn Triangle(comptime T: type) type {
    return struct {
        /// Upper-left origin is assumed, with inversed Y cartesian.
        /// Additionally, CCW point order is assumed.
        points: Vector3(Vector2(T)),

        const Self = @This();

        pub fn init(a: Vector2(T), b: Vector2(T), c: Vector2(T)) @This() {
            // todo: Assert that point order is CCW.
            return .{
                .points = Vector3(Vector2(T)).init(.{ a, b, c }),
            };
        }

        pub fn edgeWalkIterator(self: Self, comptime options: EdgeWalkIterator(T).Options) EdgeWalkIterator(T) {
            return EdgeWalkIterator(T).init(self, options);
        }
    };
}

// https://www.digipen.edu/sites/default/files/public/docs/theses/salem-haykal-digipen-master-of-science-in-computer-science-thesis-an-optimized-triangle-rasterizer.pdf
// http://groups.csail.mit.edu/graphics/classes/6.837/F98/Lecture7/triangles.html

// todo: Test horizontal line strip triangles.
pub fn EdgeWalkIterator(comptime T: type) type {
    return struct {
        inverse_slope: [3]T,

        left_edge: u3,
        right_edge: u3,

        x_end: T,
        y_end: T,

        /// Precomputed in .init(), so that .next() is denser.
        y_bottom_end: T,

        x_left: T,
        x_right: T,

        halves_left: u2,

        y: T,
        x: T,

        const Self = @This();

        pub const Options = struct {
            optimized_floats: bool = false,
        };

        pub fn init(triangle: Triangle(T), comptime options: Options) Self {
            @setFloatMode(if (options.optimized_floats) .Optimized else .Strict);

            var result: Self = undefined;
            var top: u3 = undefined;
            var middle: u3 = undefined;
            var bottom: u3 = undefined;
            var middle_is_left: u1 = undefined;

            const points = triangle.points;

            @memset(&result.inverse_slope, 0);

            // todo: Can it be better performed in SIMD?
            // Determite positions of triangle's vertices.
            if (points.at(.{ 0, 1 }) < points.at(.{ 1, 1 }))
                if (points.at(.{ 2, 1 }) < points.at(.{ 0, 1 })) {
                    top = 2;
                    middle = 0;
                    bottom = 1;
                    middle_is_left = 1;
                } else {
                    if (points.at(.{ 1, 1 }) < points.at(.{ 2, 1 })) {
                        top = 0;
                        middle = 1;
                        bottom = 2;
                        middle_is_left = 1;
                    } else {
                        top = 0;
                        middle = 2;
                        bottom = 1;
                        middle_is_left = 0;
                    }
                }
            else if (points.at(.{ 2, 1 }) < points.at(.{ 1, 1 })) {
                top = 2;
                middle = 1;
                bottom = 0;
                middle_is_left = 0;
            } else {
                top = 1;
                if (points.at(.{ 0, 1 }) < points.at(.{ 2, 1 })) {
                    middle = 0;
                    bottom = 2;
                    middle_is_left = 0;
                } else {
                    middle = 2;
                    bottom = 0;
                    middle_is_left = 1;
                }
            }

            // todo: Try doing this in SIMD.
            // Check for parallels to grid edges.
            const top_bottom_are_parallel = points.at(.{ bottom, 1 }) == points.at(.{ top, 1 });
            const top_middle_are_parallel = points.at(.{ middle, 1 }) == points.at(.{ top, 1 });
            const middle_bottom_are_parallel = points.at(.{ bottom, 1 }) == points.at(.{ middle, 1 });

            // todo: Try doing this in SIMD.
            // Set inverse slope values for triangle edges.
            if (!top_bottom_are_parallel)
                result.inverse_slope[0] = (points.at(.{ bottom, 0 }) - points.at(.{ top, 0 })) /
                    (points.at(.{ bottom, 1 }) - points.at(.{ top, 1 }));

            if (!top_middle_are_parallel)
                result.inverse_slope[1] = (points.at(.{ middle, 0 }) - points.at(.{ top, 0 })) /
                    (points.at(.{ middle, 1 }) - points.at(.{ top, 1 }));

            if (!middle_bottom_are_parallel)
                result.inverse_slope[2] = (points.at(.{ bottom, 0 }) - points.at(.{ middle, 0 })) /
                    (points.at(.{ bottom, 1 }) - points.at(.{ middle, 1 }));

            std.debug.print("{d:.3}, {d:.3}, {d:.3}\n", .{ result.inverse_slope[0], result.inverse_slope[1], result.inverse_slope[2] });

            // Determite left and right active edges.
            result.left_edge = middle_is_left;
            result.right_edge = ~middle_is_left;

            // Only bottom half is present.
            if (top_middle_are_parallel) {
                result.inverse_slope[1] = 0;

                result.y = std.math.floor(points.at(.{ middle, 1 }));
                result.y_end = std.math.ceil(points.at(.{ bottom, 1 }));

                // Set initial span.
                result.x_left = points.at(.{ result.right_edge, 0 });
                result.x_right = points.at(.{ result.left_edge, 0 });

                result.left_edge <<= 1;
                result.right_edge <<= 1;

                result.halves_left = 1;
            }

            // Only upper half is present.
            else if (middle_bottom_are_parallel) {
                result.inverse_slope[2] = 0;

                result.y = std.math.ceil(points.at(.{ top, 1 }));
                result.y_end = std.math.floor(points.at(.{ middle, 1 }));

                // Set initial x value to top vertex.
                result.x_left = points.at(.{ top, 0 }) + result.inverse_slope[result.left_edge];
                result.x_right = points.at(.{ top, 0 }) + result.inverse_slope[result.right_edge]; // Bruh.

                result.halves_left = 1;
            }

            // Regular case.
            else {
                // Split triangle from top to middle and set start and end y.
                result.y = std.math.ceil(points.at(.{ top, 1 }));
                result.y_end = std.math.floor(points.at(.{ middle, 1 }));
                result.y_bottom_end = std.math.floor(points.at(.{ bottom, 1 }));

                // Set initial x value to top vertex.
                result.x_left = points.at(.{ top, 0 }) + result.inverse_slope[result.left_edge];
                result.x_right = points.at(.{ top, 0 }) + result.inverse_slope[result.right_edge];

                result.halves_left = 2;
            }

            // Get current horizontal span to loop over.
            result.x = std.math.ceil(result.x_left);
            result.x_end = std.math.floor(result.x_right);

            return result;
        }

        pub fn next(self: *Self) ?Vector2(T) {
            if (self.halves_left == 0) return null;

            std.debug.print("{d:.3}, {d:.3} -> ", .{ self.x, self.x_end });

            defer {
                self.x += 1;
                if (self.x >= self.x_end) {
                    self.y += 1;

                    if (self.y >= self.y_end) {
                        self.halves_left -= 1;
                        if (self.halves_left != 0) {
                            self.left_edge <<= 1;
                            self.right_edge <<= 1;
                            self.y_end = self.y_bottom_end;
                        }
                    } else {
                        // todo: Trivially SIMD optimizable.
                        self.x_left += self.inverse_slope[self.left_edge];
                        self.x_right += self.inverse_slope[self.right_edge];

                        // Get current horizontal span to loop over.
                        self.x = std.math.ceil(self.x_left);
                        self.x_end = std.math.floor(self.x_right);
                    }
                }
            }

            return Vector2(T).init(.{ self.x, self.y });
        }

        pub fn writeTo(self: *Self, memory: *std.ArrayList(Vector2)) !void {
            // todo: Use approximate triangle area for allocation.

            while (self.next()) |p|
                try memory.append(p);
        }
    };
}

// todo: Needs to be rounded to integer for proper testing.
fn testTriangleRasterization(T: anytype, triangle: Triangle(T), expected: []Vector2(T)) !void {
    var it_strict = triangle.edgeWalkIterator(.{ .optimized_floats = false });
    var it_optimized = triangle.edgeWalkIterator(.{ .optimized_floats = true });
    var list = std.ArrayList(Vector2).init(std.testing.allocator);
    defer list.deinit();
    try std.testing.expectEqual(it_strict.writeTo(list).items, expected);
    list.clearAndFree();
    try std.testing.expectEqual(it_optimized.writeTo(list).items, expected);
}

test "top-parallel triangle rasterization" {
    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 2, 0 }),
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 0, 2 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 1, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 2, 0 }),
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 2, 2 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 1, 0 }),
        Vector2(f32).init(.{ 1, 1 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 2.5, 0.5 }),
        Vector2(f32).init(.{ 0.5, 0.5 }),
        Vector2(f32).init(.{ 0.5, 2.5 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 1, 0 }),
        Vector2(f32).init(.{ 2, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
        Vector2(f32).init(.{ 1, 1 }),
        Vector2(f32).init(.{ 0, 2 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 2.5, 0.5 }),
        Vector2(f32).init(.{ 0.5, 0.5 }),
        Vector2(f32).init(.{ 2.5, 2.5 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 1, 0 }),
        Vector2(f32).init(.{ 2, 0 }),
        Vector2(f32).init(.{ 1, 1 }),
        Vector2(f32).init(.{ 2, 1 }),
        Vector2(f32).init(.{ 2, 2 }),
    });
}

test "bottom-parallel triangle rasterization" {
    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 0, 2 }),
        Vector2(f32).init(.{ 2, 2 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
        Vector2(f32).init(.{ 1, 1 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 1 - std.math.floatEps(f32), 1 - std.math.floatEps(f32) }),
        Vector2(f32).init(.{ 1 - std.math.floatEps(f32), 3 - std.math.floatEps(f32) }),
        Vector2(f32).init(.{ 3 - std.math.floatEps(f32), 3 - std.math.floatEps(f32) }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 1, 1 }),
        Vector2(f32).init(.{ 1, 2 }),
        Vector2(f32).init(.{ 2, 2 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 2, 0 }),
        Vector2(f32).init(.{ 0, 2 }),
        Vector2(f32).init(.{ 2, 2 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 1, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
        Vector2(f32).init(.{ 1, 1 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 0.5, 0.5 }),
        Vector2(f32).init(.{ 0.5, 2.5 }),
        Vector2(f32).init(.{ 2.5, 2.5 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 0, 0 }),
        Vector2(f32).init(.{ 0, 1 }),
        Vector2(f32).init(.{ 1, 1 }),
        Vector2(f32).init(.{ 0, 2 }),
        Vector2(f32).init(.{ 1, 2 }),
        Vector2(f32).init(.{ 2, 2 }),
    });

    try testTriangleRasterization(f32, Triangle(f32).init(
        Vector2(f32).init(.{ 2.5, 0.5 }),
        Vector2(f32).init(.{ 0.5, 2.5 }),
        Vector2(f32).init(.{ 2.5, 2.5 }),
    ), &[_]Vector2{
        Vector2(f32).init(.{ 2, 0 }),
        Vector2(f32).init(.{ 1, 1 }),
        Vector2(f32).init(.{ 2, 1 }),
        Vector2(f32).init(.{ 0, 2 }),
        Vector2(f32).init(.{ 1, 2 }),
        Vector2(f32).init(.{ 2, 2 }),
    });
}

// todo: Ownership test for meshes.
