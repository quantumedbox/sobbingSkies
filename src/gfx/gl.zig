const std = @import("std");
const zgl = @import("zgl");
const gpu = @import("gpu.zig");
const res = @import("../res.zig");
const main = @import("../main.zig");
const shader = @import("shader.zig");
const Vector2 = @import("primitives").Vector2;
const Vector3 = @import("primitives").Vector3;

pub const quad = @import("quad.zig");
pub const triangle = @import("triangle.zig");
pub const chunk = @import("chunk.zig");

// todo: Investigate non-array attribute values as an alternative to uniforms.

pub const vertices_per_triangle = 3;
pub const vertices_per_quad = 4;
pub const elements_per_quad_face = 6;
pub const elements_per_cuboid = elements_per_quad_face * elements_per_quad_face;
pub const vertices_per_cuboid = 12;
pub const matrix_texture_resolution = 1008;
pub const matrix_texture_resolution_layers = 64; // todo: Do we need this?

pub var reusable_vertex_buffer: zgl.Buffer = .invalid;
pub var textured_program: zgl.Program = .invalid;

pub var max_texture_size: u32 = undefined;
// pub var max_rectangle_texture_size: u32 = undefined;

var was_init: bool = false;

pub fn init() !void {
    if (was_init)
        return;

    try main.init();

    // todo: Fallback to legacy extension checking.
    // if (!zgl.hasExtension("ARB_map_buffer_alignment"))
    //     @panic("No ARB_map_buffer_alignment support.");

    // todo: Have gl.zig that exposes capabilities of current context.
    max_texture_size = @as(u32, @intCast(zgl.getInteger(.max_texture_size)));
    // max_rectangle_texture_size = @as(u32, @intCast(zgl.getInteger(.max_rectangle_texture_size)));

    if (comptime std.debug.runtime_safety)
        zgl.debugMessageCallback({}, debugHandle);

    // zgl.enable(.cull_face);
    // zgl.enable(.depth_test);
    // zgl.depthFunc(.less_or_equal);
    zgl.stencilMask(0);

    reusable_vertex_buffer = zgl.createBuffer();

    var vs = try shader.compileFromResource(.vertex, try res.loadResource("shaders/textured.glsl.vert"));
    defer vs.delete();

    var fs = try shader.compileFromResource(.fragment, try res.loadResource("shaders/textured.glsl.frag"));
    defer fs.delete();

    textured_program = try shader.initProgram(&[_]zgl.Shader{ vs, fs });

    try quad.init();
    errdefer quad.deinit();

    try triangle.init();
    errdefer triangle.deinit();

    // try chunk.init();
    // errdefer chunk.deinit();

    was_init = true;
}

// todo: Color based on severity.
fn debugHandle(
    source: zgl.DebugSource,
    msg_type: zgl.DebugMessageType,
    id: usize,
    severity: zgl.DebugSeverity,
    message: []const u8,
) void {
    _ = source;
    _ = msg_type;
    _ = id;
    _ = severity;
    const stdout = std.io.getStdOut().writer();
    stdout.print("-OpenGL message: {s}\n", .{message}) catch {};
}
