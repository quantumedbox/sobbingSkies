const std = @import("std");
const sdk = @import("extern/sdl/Sdk.zig");
const zmath = @import("extern/zmath/build.zig");
const zflecs = @import("extern/zflecs/build.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Creates a step for unit testing.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    addSobbingSkies(b, unit_tests, target, optimize);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Creates a step for benchmarking.
    const exe_benchmarks = b.addExecutable(.{
        .name = "benchmarks",
        .root_source_file = .{ .path = "src/benchmarks.zig" },
        .target = target,
        .optimize = .ReleaseFast,
    });

    addSobbingSkies(b, exe_benchmarks, target, .ReleaseFast);

    const benchmark_step = b.step("benchmark", "Run all benchmarks");
    benchmark_step.dependOn(&exe_benchmarks.step);
}

pub fn addSobbingSkies(b: *std.Build, step: *std.build.CompileStep, target: std.zig.CrossTarget, optimize: std.builtin.Mode) void {
    const sdl_sdk = sdk.init(b, null);
    sdl_sdk.link(step, .dynamic);

    const zmath_pkg = zmath.package(b, target, optimize, .{ .options = .{} });
    zmath_pkg.link(step);

    const zflecs_package = zflecs.package(b, target, optimize, .{});
    zflecs_package.link(step);

    const sdl_module = sdl_sdk.getWrapperModule();
    const zgl_module = b.createModule(.{ .source_file = .{ .path = thisDir() ++ "/extern/zgl/zgl.zig" } });
    const bench_module = b.createModule(.{ .source_file = .{ .path = thisDir() ++ "/extern/zig-bench/bench.zig" } });

    const meta_module = b.createModule(.{ .source_file = .{ .path = thisDir() ++ "/src/meta/meta.zig" } });

    step.addModule("sdl", sdl_module);
    step.addModule("zgl", zgl_module);
    step.addModule("bench", bench_module);
    step.addModule("meta", meta_module);

    step.addModule("collections", b.createModule(.{ .source_file = .{ .path = thisDir() ++ "/src/collections/collections.zig" } }));
    step.addModule("gfx", b.createModule(.{ .source_file = .{ .path = thisDir() ++ "/src/gfx/gfx.zig" } }));
    step.addModule("mesh", b.createModule(.{ .source_file = .{ .path = thisDir() ++ "/src/mesh/mesh.zig" } }));
    step.addModule("primitives", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/primitives/primitives.zig" },
        .dependencies = &[_]std.Build.ModuleDependency{
            .{ .name = "meta", .module = meta_module },
        },
    }));
    step.addModule("runner", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/src/runner/runner.zig" },
        .dependencies = &[_]std.Build.ModuleDependency{
            .{ .name = "sdl", .module = sdl_module },
            .{ .name = "zgl", .module = zgl_module },
        },
    }));
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
