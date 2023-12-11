const std = @import("std");
const zgl = @import("zgl");
const res = @import("../res.zig");
const gfx = @import("gfx.zig");

// todo: Use init counter instead.
var was_init: bool = false;

/// In CCW order.
pub const ScreenspaceTriangle = struct {
    a: @Vector(2, f32),
    b: @Vector(2, f32),
    c: @Vector(2, f32),
};

pub fn renderScreenspaceTriangles(triangles: []const ScreenspaceTriangle) void {
    const ScreenspaceTriangleVertex = packed struct {
        x: f32,
        y: f32,
        uv_x: u16,
        uv_y: u16,
    };

    gfx.reusable_vertex_buffer.bind(.array_buffer);
    zgl.bufferUninitialized(
        .array_buffer,
        ScreenspaceTriangleVertex,
        triangles.len * gfx.vertices_per_triangle,
        .stream_draw,
    );

    var buf = @as([]align(64) ScreenspaceTriangleVertex, @alignCast(zgl.mapBufferRange(
        .array_buffer,
        ScreenspaceTriangleVertex,
        0,
        triangles.len * gfx.vertices_per_triangle,
        .{ .write = true },
    )));

    for (triangles, 0..) |triangle, i| {
        const offset = i * gfx.vertices_per_triangle;
        buf[offset + 0] = ScreenspaceTriangleVertex{
            .x = triangle.a[0],
            .y = triangle.a[1],
            .uv_x = 0,
            .uv_y = 1,
        };
        buf[offset + 1] = ScreenspaceTriangleVertex{
            .x = triangle.b[0],
            .y = triangle.b[1],
            .uv_x = 1,
            .uv_y = 1,
        };
        buf[offset + 2] = ScreenspaceTriangleVertex{
            .x = triangle.c[0],
            .y = triangle.c[1],
            .uv_x = 0,
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
        @sizeOf(ScreenspaceTriangleVertex),
        @offsetOf(ScreenspaceTriangleVertex, "x"),
    );
    zgl.enableVertexAttribArray(0);
    zgl.vertexAttribPointer(
        1,
        2,
        .unsigned_short,
        true,
        @sizeOf(ScreenspaceTriangleVertex),
        @offsetOf(ScreenspaceTriangleVertex, "uv_x"),
    );
    zgl.enableVertexAttribArray(1);

    zgl.drawArrays(.triangles, 0, triangles.len * gfx.vertices_per_triangle);
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
