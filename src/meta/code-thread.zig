//! Threaded code interface to allow piping of effectual procedures.
//! Could be used for mix-in logging, diagnostics, book-keeping, parameter checking and etc. without introducing major overhead.

// todo: Alternative interface is possible with TLS stack of threads, so that any procedure could be stacked, without prototypes being different.

const std = @import("std");

pub fn CodeThread(comptime Prototype: type) type {
    return struct {
        callbacks: []const Callback,

        pub const Callback = *const anyopaque;
        pub const ReturnType = @typeInfo(Prototype).Fn.return_type.?;

        const Self = @This();

        pub fn init(callbacks: []const Callback) Self {
            return .{ .callbacks = callbacks };
        }

        pub fn call(self: Self, args: anytype) ReturnType {
            return @call(.auto, @as(
                *const Prototype,
                @ptrCast(self.callbacks[0]),
            ), .{self.callbacks[1..]} ++ args);
        }

        /// Note: It will panic if there's nothing to call.
        pub inline fn next(context: []const Callback, args: anytype) ReturnType {
            return @call(.always_tail, @as(
                *const Prototype,
                @ptrCast(context[0]),
            ), .{context[1..]} ++ args);
        }
    };
}

test "test of parameters for computation" {
    // Inability to self reference here kinda makes it ugly. We could create this type automatically.
    const Thread = CodeThread(fn ([]const *const anyopaque, u32, u32) u64);

    const Funcs = struct {
        // Leaf function.
        fn addOddAndEven(context: []const Thread.Callback, a: u32, b: u32) u64 {
            _ = context;
            return a + b;
        }
        // A mixin.
        fn doTest(context: []const Thread.Callback, a: u32, b: u32) u64 {
            if (a % 2 == b % 2) @panic("Invalid input");
            return Thread.next(context, .{ a, b });
        }
    };

    try std.testing.expectEqual(Thread.init(&[_]Thread.Callback{
        &Funcs.doTest,
        &Funcs.addOddAndEven,
    }).call(.{ 2, 3 }), 5);
}
