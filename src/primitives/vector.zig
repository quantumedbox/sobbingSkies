//! Vector type that solves following cases:
//! - Arbitrary arity.
//! - Use of arbitrary identypes for positions, including unsigned and varying bit count.
//! - SIMD for numerical primitives.
//! - User defined types that come with arithmetic interface.
//! - Inlined store of nested vectors, such as Vector3(Vector2(f32)), resulting in |xyxyxy--|

const std = @import("std");
const isTypeIdenitityMatching = @import("meta").isTypeIdenitityMatching;

// todo: Arbitrary function application in per-element fashion, for function style programming.
// todo: Swizzling function.
// todo: Inline stored and operated SIMD vectors of vectors, this would allow for efficient matrices and representation of bounding rectangles.
// todo: Hide irrelevant for particular len methods.
// todo: Dimensiality declaration, as a comptime array.
// todo: Support for arbitrary nested vectors being inlined.
// todo: Support for non-interleaved nested vectors.
// todo: Support for types such as struct-based fixed point to implement SIMD ops. Or rather, default to SIMD mode.

const vector_type_identity = "primitives/vec.zig/GenericVector";

/// Note that upper-left origin is assumed, where X grows rightwards and Y grows downwards.
pub fn GenericVector(
    comptime len: usize,
    comptime T: type,
    comptime options: struct {},
) type {
    _ = options;

    return struct {
        components: Components,

        pub const type_identity = vector_type_identity;

        pub const is_numerical = switch (@typeInfo(T)) {
            .Int, .Float, .Bool => true,
            else => false,
        };

        pub const arity = len;
        pub const dimensionality = if (isTypeIdenitityMatching(T, vector_type_identity)) T.dimensionality + 1 else 1;
        pub const is_inlined = isTypeIdenitityMatching(T, vector_type_identity) and T.is_numerical;
        pub const Item = if (is_inlined) T.Item else T;
        pub const Child = T;

        pub const Components = if (is_inlined) @Type(
            std.builtin.Type{ .Vector = .{ .len = len * T.arity, .child = Item } },
        ) else if (is_numerical)
            @Type(std.builtin.Type{ .Vector = .{ .len = len, .child = Item } })
        else
            @Type(std.builtin.Type{ .Array = .{ .len = len, .child = Item, .sentinel = null } });

        pub const component_count = if (is_inlined) len * T.arity else len;

        pub const Elements = if (is_numerical)
            @Type(std.builtin.Type{ .Vector = .{ .len = len, .child = T } })
        else
            @Type(std.builtin.Type{ .Array = .{ .len = len, .child = T, .sentinel = null } });

        pub const zero = @This(){ .components = .{@as(Item, @intCast(0))} ** len };
        pub const center = @This(){ .components = .{coordinateCenter(Item)} ** len };

        const Self = @This();

        fn DimensionT(comptime level: usize) type {
            var C = Child;
            inline for (0..level) |_|
                C = C.Child;

            return C;
        }

        fn DimensionArity(comptime level: usize) comptime_int {
            const D = DimensionT(level);
            return if (isTypeIdenitityMatching(D, vector_type_identity)) D.arity else 1;
        }

        pub inline fn init(elements: Elements) Self {
            var result: Self = undefined;
            inline for (0..arity) |i|
                result.set(i, elements[i]);
            return result;
        }

        pub inline fn index(self: Self, idx: usize) T {
            return if (comptime is_inlined) brk: {
                // todo: This generates awful assemly.
                const dest: [component_count]Item = self.components;
                const vec: T.Components = dest[idx * T.arity .. idx * T.arity + T.arity][0..T.component_count].*;
                break :brk T{ .components = vec };
            } else self.components[idx];
        }

        pub inline fn set(self: *Self, idx: usize, value: T) void {
            if (comptime is_inlined) {
                // todo: This generates awful assembly.
                var dest: [component_count]Item = self.components;
                const source: [T.arity]Item = value.components;
                @memcpy(dest[idx * T.arity .. idx * T.arity + T.arity], &source);
                self.components = dest;
            } else self.components[idx] = value;
        }

        /// Extract leaf element from multidimensional vector.
        /// Order of indexes is from outer towards inner.
        pub inline fn at(self: Self, addr: [dimensionality]usize) Item {
            var idx: usize = 0;
            inline for (addr, 0..) |i, level|
                idx += i * DimensionArity(level);

            return self.components[idx];
        }

        pub fn fromScalar(scalar: T) Self {
            return .{ .components = .{scalar} ** len };
        }

        pub fn as(self: Self, comptime To: type) GenericVector(len, To) {
            var result: GenericVector(len, T).Components = undefined;
            inline for (result, 0..) |*v, i|
                v.* = @as(To, @intCast(self.components[i]));
            return result;
        }

        // todo: Generic rotation function that would optimize for comptime_int cases?
        const TwoComponentInterface = struct {
            pub inline fn x(self: Self) T {
                return self.index(0);
            }
            pub inline fn y(self: Self) T {
                return self.index(1);
            }
            pub const r = x;
            pub const g = y;

            pub const Axis = enum { x, y };

            // todo: Use .negate() interface for user types.
            pub fn rotateByHalfPiClockwise(self: Self) Self {
                return .{ .components = .{ -self.y(), self.x() } };
            }

            pub fn rotateByHalfPiCounterClockwise(self: Self) Self {
                return .{ .components = .{ self.y(), -self.x() } };
            }

            pub fn rotateByPi(self: Self) Self {
                return .{ .components = .{ -self.x(), -self.y() } };
            }
        };

        const ThreeComponentInterface = struct {
            pub inline fn x(self: Self) T {
                return self.index(0);
            }
            pub inline fn y(self: Self) T {
                return self.index(1);
            }
            pub inline fn z(self: Self) T {
                return self.index(2);
            }
            pub const r = x;
            pub const g = y;
            pub const b = z;

            pub const Axis = enum { x, y, z };

            // todo: Use .negate() interface for user types.
            pub fn rotateByHalfPiClockwiseAroundAxis(self: Self, axis: Axis) Self {
                return .{ .components = switch (axis) {
                    .x => .{ self.x(), -self.z(), self.y() },
                    .y => .{ -self.z(), self.y(), self.x() },
                    .z => .{ -self.y(), self.x(), self.z() },
                } };
            }

            pub fn rotateByHalfPiCounterClockwiseAroundAxis(self: Self, axis: Axis) Self {
                return .{ .components = switch (axis) {
                    .x => .{ self.x(), self.z(), -self.y() },
                    .y => .{ self.z(), self.y(), -self.x() },
                    .z => .{ self.y(), -self.x(), self.z() },
                } };
            }

            pub fn rotateByPiAroundAxis(self: Self, axis: Axis) Self {
                return .{ .components = switch (axis) {
                    .x => .{ self.x(), -self.x(), -self.y() },
                    .y => .{ -self.x(), self.y(), -self.z() },
                    .z => .{ -self.x(), -self.y(), self.z() },
                } };
            }
        };

        pub usingnamespace switch (len) {
            2 => TwoComponentInterface,
            3 => ThreeComponentInterface,
            else => .{},
        };

        pub fn add(self: Self, other: Self) Self {
            if (is_numerical) return .{ .components = self.components + other.components } else {
                return .{ .components = blk: {
                    var result: Components = undefined;
                    inline for (result, 0..) |*v, i|
                        v.* = self.components[i].add(other.components[i]);
                    break :blk;
                } };
            }
        }

        const SignedCounterpart = switch (@typeInfo(T).Int.signedness) {
            .signed => T,
            .unsigned => |int| std.meta.Int(.signed, int.bits),
        };

        const RelativeDifference = switch (@typeInfo(T).Int.signedness) {
            .signed => T,
            .unsigned => |int| std.meta.Int(.signed, int.bits + 1),
        };

        pub fn addSigned(self: Self, other: GenericVector(len, SignedCounterpart)) Self {
            return .{ .components = blk: {
                var result: Components = undefined;
                inline for (result, 0..) |*v, i|
                    v.* = @as(T, @intCast(@as(RelativeDifference, @intCast(self.components[i])) + other.components[i]));
                break :blk result;
            } };
        }

        pub fn addWithOverflow(self: Self, other: Self) Self {
            return .{ .components = blk: {
                var result: Components = undefined;
                inline for (result, 0..) |*v, i|
                    v.* = @addWithOverflow(self.components[i], other.components[i]).@"0";
                break :blk result;
            } };
        }

        pub fn subtract(self: Self, other: Self) Self {
            if (is_numerical) return .{ .components = self.components - other.components } else {
                return .{ .components = blk: {
                    var result: Components = undefined;
                    inline for (result, 0..) |*v, i|
                        v.* = self.components[i].subtract(other.components[i]);
                    break :blk result;
                } };
            }
        }

        pub fn absoluteDifference(self: Self, other: Self) Self {
            return switch (@typeInfo(T).Int.signedness) {
                .signed => self.subtract(other),
                .unsigned => .{ .components = blk: {
                    var result: Components = undefined;
                    inline for (result, 0..) |*v, i| {
                        if (self.components[i] >= other.components[i])
                            v.* = self.components[i] - other.components[i]
                        else
                            v.* = other.components[i] - self.components[i];
                    }
                    break :blk result;
                } },
            };
        }

        // todo: Unit test.
        /// Note that for unsigned types it returns signed components with 1 bit extended as required fod holding all possible cases.
        pub fn relativeDifference(self: Self, other: Self) GenericVector(len, RelativeDifference) {
            return switch (@typeInfo(T).Int.signedness) {
                .signed => self.subtract(other),
                .unsigned => .{ .components = blk: {
                    var result: Components = undefined;
                    inline for (result, 0..) |*v, i| {
                        if (self.components[i] >= other.components[i])
                            v.* = self.components[i] - other.components[i]
                        else
                            v.* = -@as(RelativeDifference, @intCast(other.components[i] - self.components[i]));
                    }
                    break :blk result;
                } },
            };
        }

        // todo: Variant that calculates distance for any value by returning type with sufficient range.
        pub fn euclideanDistanceSquared(self: Self) T {
            if (is_numerical) return @reduce(.Add, self.components * self.components) else {
                var temp: Components = undefined;
                inline for (temp, 0..) |*v, i|
                    v.* = self.components[i].multiply(self.components[i]);
                var result: T = temp[0];
                inline for (temp[1..]) |v| result = result.add(v);
                return result;
            }
        }
    };
}

pub inline fn Vector2(comptime T: type) type {
    return GenericVector(2, T, .{});
}

pub inline fn Vector3(comptime T: type) type {
    return GenericVector(3, T, .{});
}

pub inline fn Vector4(comptime T: type) type {
    return GenericVector(4, T, .{});
}

// todo: Move somewhere.
fn coordinateCenter(comptime T: type) T {
    return switch (@typeInfo(T).Int.signedness) {
        .signed => 0,
        .unsigned => std.math.maxInt(T) / 2,
    };
}
