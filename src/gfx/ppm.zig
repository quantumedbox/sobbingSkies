const std = @import("std");
const gen = @import("gen.zig");
const Chunk = @import("chunk.zig").Chunk;

// https://netpbm.sourceforge.net/doc/ppm.html

// note: Image is flipped vertically.
pub fn writeChunkHeightmapsResultToFile(
    file: std.fs.File,
    heightmaps: *const gen.ChunkHeightmaps.Result,
    requests: []const Chunk.PositionPlane,
    allocator: std.mem.Allocator,
) !void {
    const columns = @min(requests.len, @as(usize, gen.heightmap_framebuffer_dimension) / heightmaps.resolution);
    const rows = requests.len / columns;

    try writeHeader(file, columns * heightmaps.resolution, rows * heightmaps.resolution);

    // todo: Use temporary reuse allocator.
    var buf = try allocator.alloc(u16, columns * heightmaps.resolution * 3);
    defer allocator.free(buf);

    @memset(buf, 0);

    for (0..rows) |row| {
        for (0..heightmaps.resolution) |y| {
            for (0..columns) |column| {
                const points = heightmaps.getChunk(column + row * columns);
                for (0..heightmaps.resolution) |x| {
                    buf[(x + column * heightmaps.resolution) * 3] = std.mem.nativeTo(u16, points[x + y * heightmaps.resolution], .Big);
                }
            }
            _ = try file.write(@as([*]u8, @ptrCast(buf))[0 .. columns * heightmaps.resolution * 6]);
        }
    }
}

fn writeHeader(file: std.fs.File, w: usize, h: usize) !void {
    var buf: [64]u8 = undefined;

    _ = try file.write("P6 ");
    _ = try file.write(try std.fmt.bufPrint(&buf, "{d} ", .{w}));
    _ = try file.write(try std.fmt.bufPrint(&buf, "{d} ", .{h}));
    _ = try file.write(try std.fmt.bufPrint(&buf, "{d} ", .{std.math.maxInt(u16)}));
}
