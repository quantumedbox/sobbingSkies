const std = @import("std");
const zgl = @import("zgl");
const res = @import("../res.zig");
const gfx = @import("gfx.zig");

// todo: Use init counter instead.
var was_init: bool = false;

pub const ScreenspaceQuad = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub fn renderScreenspaceQuads(quads: []const ScreenspaceQuad) void {
    const ScreenspaceQuadVertex = packed struct {
        x: f32,
        y: f32,
        uv_x: u16,
        uv_y: u16,
    };

    gfx.reusable_vertex_buffer.bind(.array_buffer);
    zgl.bufferUninitialized(
        .array_buffer,
        ScreenspaceQuadVertex,
        quads.len * gfx.vertices_per_quad,
        .stream_draw,
    );

    var buf = @as([]align(64) ScreenspaceQuadVertex, @alignCast(zgl.mapBufferRange(
        .array_buffer,
        ScreenspaceQuadVertex,
        0,
        quads.len * gfx.vertices_per_quad,
        .{ .write = true },
    )));

    for (quads, 0..) |quad, i| {
        const offset = i * gfx.vertices_per_quad;
        buf[offset + 0] = ScreenspaceQuadVertex{
            .x = quad.x - quad.w,
            .y = quad.y - quad.h,
            .uv_x = 0,
            .uv_y = @as(u16, @intFromFloat(quad.h * 65535.0)),
        };
        buf[offset + 1] = ScreenspaceQuadVertex{
            .x = quad.x + quad.w,
            .y = quad.y - quad.h,
            .uv_x = @as(u16, @intFromFloat(quad.w * 65535.0)),
            .uv_y = @as(u16, @intFromFloat(quad.h * 65535.0)),
        };
        buf[offset + 2] = ScreenspaceQuadVertex{
            .x = quad.x - quad.w,
            .y = quad.y + quad.h,
            .uv_x = 0,
            .uv_y = 0,
        };
        buf[offset + 3] = ScreenspaceQuadVertex{
            .x = quad.x + quad.w,
            .y = quad.y + quad.h,
            .uv_x = @as(u16, @intFromFloat(quad.w * 65535.0)),
            .uv_y = 0,
        };
    }

    if (!zgl.unmapBuffer(.array_buffer))
        @panic("Unmap failed");

    gfx.textured_program.use();

    zgl.bindVertexArray(.invalid);
    zgl.vertexAttribPointer(
        0,
        2,
        .float,
        false,
        @sizeOf(ScreenspaceQuadVertex),
        @offsetOf(ScreenspaceQuadVertex, "x"),
    );
    zgl.enableVertexAttribArray(0);
    zgl.vertexAttribPointer(
        1,
        2,
        .unsigned_short,
        true,
        @sizeOf(ScreenspaceQuadVertex),
        @offsetOf(ScreenspaceQuadVertex, "uv_x"),
    );
    zgl.enableVertexAttribArray(1);

    // todo: It doesn't work for mltiple quads, bruh.
    zgl.drawArrays(.triangle_strip, 0, 4 * quads.len);
    zgl.invalidateBufferData(gfx.reusable_vertex_buffer);
}

pub fn init() !void {
    if (was_init)
        return;

    was_init = true;
}

pub fn deinit() void {
    if (!was_init)
        return;
}
