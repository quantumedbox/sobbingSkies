const builtin = @import("builtin");

// Try to force devices with different available graphics units to use the most performant one.
comptime {
    if (builtin.os.tag == .windows) {
        // https://stackoverflow.com/questions/68469954/how-to-choose-specific-gpu-when-create-opengl-context
        const NvOptimusEnablement: u32 = 1;
        const AmdPowerXpressRequestHighPerformance: c_int = 1;

        @export(NvOptimusEnablement, .{ .linkage = .default });
        @export(AmdPowerXpressRequestHighPerformance, .{ .linkage = .default });
    }
}
