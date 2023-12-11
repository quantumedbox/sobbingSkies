const std = @import("std");
const benchmark = @import("bench").benchmark;

pub fn main() !void {
    try benchmark(struct {
        pub const min_iterations = 100;
        pub const max_iterations = 100;
    });
}
