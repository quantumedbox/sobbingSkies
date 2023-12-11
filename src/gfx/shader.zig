const std = @import("std");
const zgl = @import("zgl");
const res = @import("../res.zig");

// todo: Intermediate shader lisp-like language that could polyfill apis, extensions,
//       hardware constraints and ways particular hardware most effective at.
//
//       Helpful things would be:
//          - Rectangular texture polyfill, useful for GLES.
//          - Temporaries of operations or their direct pasting, sometimes recalculating is faster.
//          - Texture swizzle vs vec4(texture2D(texture).xyz, 1.0).
//          - Numeric constants vs uniforms. (Tegra prefers uniforms, for example)
//          - Attribute packing. (Tegra prefers packing, but some Qualcomm devices prefer separation, for example)
//

// todo: Reloadable file watching shaders.

pub fn initProgram(shaders: []const zgl.Shader) !zgl.Program {
    if (shaders.len == 0)
        return error.UnexpectedError;

    const program = zgl.createProgram();

    for (shaders) |shader| {
        program.attach(shader);
    }

    program.link();

    if (comptime std.debug.runtime_safety) {
        if (program.get(.link_status) == 0) {
            const stdout = std.io.getStdOut().writer();
            const allocator = std.heap.page_allocator;
            const log = try program.getCompileLog(allocator);
            defer allocator.free(log);

            try stdout.print("Error on program link, log:\n{s}\n", .{log});

            return error.UnexpectedError;
        }
    }

    return program;
}

pub fn compile(stype: zgl.ShaderType, source: []const u8) !zgl.Shader {
    const sh = zgl.createShader(stype);

    sh.source(1, &[_][]const u8{source});
    sh.compile();

    if (sh.get(.compile_status) == 0) {
        const stdout = std.io.getStdOut().writer();
        const allocator = std.heap.page_allocator;
        const log = try sh.getCompileLog(allocator);
        defer allocator.free(log);

        try stdout.print("Error on {any} shader compilation, log:\n{s}\n", .{ stype, log });

        return error.UnexpectedError;
    }

    return sh;
}

pub fn compileFromResource(stype: zgl.ShaderType, resource: res.Resource) !zgl.Shader {
    // fixme: Memory leak.
    // defer resource.free();
    return try compile(stype, resource.getData());
}
