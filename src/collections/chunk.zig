const std = @import("std");
const benchmark = @import("bench").benchmark;
const block = @import("block.zig");
const Vector3 = @import("vec.zig").Vector3;

// todo: https://en.wikipedia.org/wiki/Z-order_curve
//       https://stackoverflow.com/questions/39490345/interleave-bits-efficiently

// todo: Rework to generic.

const alignment = 64;

pub const Chunk = struct {
    blocks: [volume]block.Id align(alignment),

    pub const depth = 32;
    pub const face_area = depth * depth;
    pub const volume = face_area * depth;

    // todo: No absolute positioning.
    pub const Position = Vector3(PositionElement);
    pub const PositionPlane = struct { x: PositionElement, z: PositionElement };
    // Chosen as it needs to be converted to floating point for generation.
    // GLES 2.0 guarantees that highp is at least capable of holding ±65,504 integer range.
    pub const PositionElement = u16;

    pub const Index = struct {
        offset: u15,

        pub inline fn at(x: u5, y: u5, z: u5) Index {
            return Index{ .offset = @as(u15, @intCast(x)) + @as(u15, @intCast(y)) * Chunk.depth + @as(u15, @intCast(z)) * Chunk.face_area };
        }

        pub inline fn nextX(self: Index) Index {
            return Index{ .offset = self.offset + 1 };
        }

        pub inline fn nextY(self: Index) Index {
            return Index{ .offset = self.offset + Chunk.depth };
        }

        pub inline fn nextZ(self: Index) Index {
            return Index{ .offset = self.offset + Chunk.face_area };
        }

        pub inline fn next(self: Index, comptime dir: enum { x, y, z, xy, xz, yz, xyz }) Index {
            return switch (dir) {
                .x => nextX(self),
                .y => nextY(self),
                .z => nextZ(self),
                .xy => nextY(nextX(self)),
                .xz => nextZ(nextX(self)),
                .yz => nextZ(nextY(self)),
                .xyz => nextZ(nextY(nextX(self))),
            };
        }
    };

    pub inline fn init() Chunk {
        return Chunk{ .blocks = [_]block.Id{0} ** volume };
    }

    pub inline fn index(self: *const Chunk, idx: Index) block.Id {
        return self.blocks[idx.offset];
    }

    pub fn fill(self: *Chunk, x: u5, y: u5, z: u5, w: u5, h: u5, d: u5, id: block.Id) void {
        // todo: Can be a lot smarter.
        var iz: u15 = 0;
        while (iz < @as(u15, d) + 1) : (iz += 1) {
            var iy: u15 = 0;
            while (iy < @as(u15, h) + 1) : (iy += 1) {
                var ix: u15 = 0;
                while (ix < @as(u15, w) + 1) : (ix += 1) {
                    self.blocks[ix + x + (iy + y) * Chunk.depth + (iz + z) * Chunk.face_area] = id;
                }
            }
        }
    }

    pub fn segment(self: *const Chunk, allocator: std.mem.Allocator) !SegmentedChunk {
        const shadow_bit = 0b10000000;

        const ShadowSegment = struct {
            id: block.Id,
            // Last bit of x is reserved to signal shadowed segment.
            // As it will not ever be copied to result segments it's fine.
            x: u8,
            y: u5,
            z: u5,
            w: u5,
            h: u5,
            d: u5,
        };

        // todo: Make it thread local.
        // todo: It's quite a big chunk of memory that otherwise doesn't do anything outside of this function,
        //       we should implement thread local temporary storage model.
        //
        const local = struct {
            var builder: [Chunk.volume]ShadowSegment = undefined;
        };

        var idx: u16 = 0; // Current block
        var segment_idx: u15 = 0; // Current segment
        var shadowed_count: u15 = 0; // todo: As X axis cannot be shadowed actual integer range is smaller than u15

        var h_merger_idx: u15 = undefined;
        var h_tail_idx: u15 = undefined;

        var d_merger_idx: u15 = 0;
        var d_tail_idx: u15 = undefined;

        var z: u8 = 0;
        while (z < 32) : (z += 1) {
            h_merger_idx = segment_idx;

            var y: u8 = 0;
            while (y < 32) : (y += 1) {
                var x: u8 = 0;
                while (x < 32) : ({
                    x += 1;
                    idx += 1;
                }) {
                    if (x != 0 and self.blocks[idx] == local.builder[segment_idx - 1].id) {
                        local.builder[segment_idx - 1].w += 1;
                    } else {
                        local.builder[segment_idx] = ShadowSegment{ .id = self.blocks[idx], .x = @as(u5, @intCast(x)), .y = @as(u5, @intCast(y)), .z = @as(u5, @intCast(z)), .w = 0, .h = 0, .d = 0 };
                        segment_idx += 1;
                    }
                }

                if (y != 0) {
                    const h_tail_idx_cached = h_tail_idx;

                    while (h_merger_idx < h_tail_idx_cached and h_tail_idx < segment_idx) {
                        if (local.builder[h_merger_idx].x < local.builder[h_tail_idx].x) {
                            h_merger_idx += 1;
                        } else if (local.builder[h_merger_idx].x > local.builder[h_tail_idx].x) {
                            h_tail_idx += 1;
                        } else if (local.builder[h_merger_idx].id == local.builder[h_tail_idx].id and
                            local.builder[h_merger_idx].w == local.builder[h_tail_idx].w)
                        {
                            local.builder[h_tail_idx].h = local.builder[h_merger_idx].h + 1;
                            local.builder[h_merger_idx].x |= shadow_bit;
                            shadowed_count += 1;
                            h_tail_idx += 1;
                            h_merger_idx += 1;
                        } else {
                            h_tail_idx += 1;
                            h_merger_idx += 1;
                        }
                    }

                    h_merger_idx = h_tail_idx_cached;
                }

                h_tail_idx = segment_idx;
            }

            if (z != 0) {
                const d_tail_idx_cached = d_tail_idx;

                while (d_merger_idx < d_tail_idx_cached and d_tail_idx < segment_idx) {
                    if (local.builder[d_merger_idx].x < local.builder[d_tail_idx].x or
                        local.builder[d_merger_idx].y < local.builder[d_tail_idx].y)
                    {
                        d_merger_idx += 1;
                    } else if (local.builder[d_merger_idx].x > local.builder[d_tail_idx].x or
                        local.builder[d_merger_idx].y > local.builder[d_tail_idx].y)
                    {
                        d_tail_idx += 1;
                    } else if (local.builder[d_merger_idx].id == local.builder[d_tail_idx].id and
                        (local.builder[d_merger_idx].x & shadow_bit) == 0 and
                        (local.builder[d_tail_idx].x & shadow_bit) == 0 and
                        local.builder[d_merger_idx].w == local.builder[d_tail_idx].w and
                        local.builder[d_merger_idx].h == local.builder[d_tail_idx].h)
                    {
                        local.builder[d_tail_idx].d = local.builder[d_merger_idx].d + 1;
                        local.builder[d_merger_idx].x |= shadow_bit;
                        shadowed_count += 1;
                        d_tail_idx += 1;
                        d_merger_idx += 1;
                    } else {
                        d_tail_idx += 1;
                        d_merger_idx += 1;
                    }
                }

                d_merger_idx = d_tail_idx_cached;
            }

            d_tail_idx = segment_idx;
        }

        const result = try allocator.alloc(SegmentedChunk.Segment, segment_idx - shadowed_count);
        var w: u15 = 0;
        var i: u15 = 0;
        while (i < segment_idx) : (i += 1) {
            if ((local.builder[i].x & shadow_bit) == 0) {
                std.debug.assert(w < segment_idx - shadowed_count);

                // todo: We could collect sequential non shadowed segments and use single copy function call,
                //       making it potentially quite a lot cheaper.
                result[w] = @as(*SegmentedChunk.Segment, @ptrCast(&local.builder[i])).*;
                w += 1;
            }
        }

        return SegmentedChunk{ .segments = result };
    }
};

pub const SegmentedChunk = struct {
    segments: []Segment,

    const Segment = struct {
        id: block.Id,
        x: u5,
        y: u5,
        z: u5,
        w: u5,
        h: u5,
        d: u5,
    };
};

test "single segment chunk" {
    const chunk = Chunk.init();
    const segmented = try chunk.segment(std.testing.allocator);
    defer std.testing.allocator.free(segmented.segments);

    try std.testing.expect(segmented.segments.len == 1);
    try std.testing.expect(segmented.segments[0].id == 0);
    try std.testing.expect(segmented.segments[0].x == 0);
    try std.testing.expect(segmented.segments[0].y == 31);
    try std.testing.expect(segmented.segments[0].z == 31);
    try std.testing.expect(segmented.segments[0].w == 31);
    try std.testing.expect(segmented.segments[0].h == 31);
    try std.testing.expect(segmented.segments[0].d == 31);
}

test "two segment chunk" {
    var chunk = Chunk.init();
    chunk.fill(0, 0, 0, 31, 31, 15, 1);

    const segmented = try chunk.segment(std.testing.allocator);
    defer std.testing.allocator.free(segmented.segments);

    try std.testing.expect(segmented.segments.len == 2);

    try std.testing.expect(segmented.segments[0].id == 1);
    try std.testing.expect(segmented.segments[0].x == 0);
    try std.testing.expect(segmented.segments[0].y == 31);
    try std.testing.expect(segmented.segments[0].z == 15);
    try std.testing.expect(segmented.segments[0].w == 31);
    try std.testing.expect(segmented.segments[0].h == 31);
    try std.testing.expect(segmented.segments[0].d == 15);

    try std.testing.expect(segmented.segments[1].id == 0);
    try std.testing.expect(segmented.segments[1].x == 0);
    try std.testing.expect(segmented.segments[1].y == 31);
    try std.testing.expect(segmented.segments[1].z == 31);
    try std.testing.expect(segmented.segments[1].w == 31);
    try std.testing.expect(segmented.segments[1].h == 31);
    try std.testing.expect(segmented.segments[1].d == 15);
}
