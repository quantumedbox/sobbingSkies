const std = @import("std");
const zgl = @import("zgl");
const res = @import("../res.zig");
const gfx = @import("gfx.zig");
const chunk = @import("chunk.zig");
const raster = @import("primitives").raster;
const shader = @import("shader.zig");
const BufferHeap = @import("buffer-heap.zig").BufferHeap;

const front_facing_indices_per_segment = 18;
const chunk_far_quad_indices_count = 10922; // How many far quad indices are preallocated.

var chunk_quad_program: zgl.Program = .invalid;
var chunk_far_quad_indices: zgl.Buffer = .invalid;

var segment_vertex_array: zgl.VertexArray = undefined;

var was_init: bool = false;

// If vertex processing is not a bottleneck, it is worthwhile to run experiments that prime the depth buffer in a first pass.
// Disable all color writes with ColorMask on the first pass. The fragments in the depth buffer can then serve as an occluder
// in a second pass when color writes are enabled and the expensive fragment shaders are executed.
// Disable depth writes with DepthMask in the second pass since there is no point in writing it twice.
//
// todo: Consider exploiting MIRRORED_REPEAT to reduce memory usage and increase cache hits in exchange for visual variety.

pub const ChunkBatch = struct {
    matrices: zgl.Texture,
    heap: BufferHeap,
    configuration: Configuration,

    pub const Configuration = struct {
        full_radius: usize,
        half_radius: usize,
        quarter_radius: usize,

        full_chunks: usize,
        half_chunks: usize,
        quarter_chunks: usize,

        pub fn init(full_radius: usize, half_radius: usize, quarter_radius: usize) @This() {
            const full_chunks = raster.circleArea(full_radius);
            const half_chunks = raster.ringArea(full_radius, half_radius);
            const quarter_chunks = raster.ringArea(half_radius, quarter_radius);
            return @This(){
                .full_radius = full_radius,
                .half_radius = half_radius,
                .quarter_radius = quarter_radius,
                .full_chunks = full_chunks,
                .half_chunks = half_chunks,
                .quarter_chunks = quarter_chunks,
            };
        }
    };

    const FarQuadVertex = packed struct {
        x: u8,
        y: u16,
        z: u8,
        uv_x: u8,
        uv_y: u8,
        uvs_x: u8,
        uvs_y: u8,
    };

    pub fn init(allocation: std.mem.Allocator, configuration: Configuration) !@This() {
        var heap = try BufferHeap.init(allocation, .{});

        var matrices = zgl.genTexture();
        matrices.bind(.rectangle);
        zgl.texParameter(.rectangle, .min_filter, .nearest);
        zgl.texParameter(.rectangle, .mag_filter, .nearest);
        // todo: Half float might be sufficient.
        zgl.texStorage2D(.rectangle, 1, .rgba32f, gfx.matrix_texture_resolution, gfx.matrix_texture_resolution_layers);

        var far_quad_vertex_array = zgl.genVertexArray();
        far_quad_vertex_array.bind();
        zgl.vertexAttribIPointer(
            0,
            4,
            .unsigned_byte,
            @sizeOf(FarQuadVertex),
            @offsetOf(FarQuadVertex, "x"),
        );
        zgl.enableVertexAttribArray(0);
        zgl.vertexAttribIPointer(
            1,
            4,
            .unsigned_byte,
            @sizeOf(FarQuadVertex),
            @offsetOf(FarQuadVertex, "uv_x"),
        );
        zgl.enableVertexAttribArray(1);

        return @This(){
            .matrices = matrices,
            .far_quad_vertex_array = far_quad_vertex_array,
            .heap = heap,
            .configuration = configuration,
        };
    }

    // todo: Batch should know the size of frame it's cooking, as server buffer resizes drop the contents.
    //       For that it probably should receive a slice of chunks that are going to be rendered.
    //
    //       Alternitively we could use just copy the memory to new buffer.
    //       https://stackoverflow.com/questions/27751101/how-do-i-grow-a-buffer-opengl
    //
    pub fn render(self: @This()) void {
        chunk_quad_program.use();
        self.far_quad_vertex_array.bind();
        // todo: Commit wrapping of it in zgl.
        // zglb.multiDrawElementsBaseVertex(zglb.TRIANGLES, zglb.UNSIGNED_INT);
    }

    pub fn free(self: *@This()) void {
        self.positions.delete();
        self.far_quad_vertex_array.delete();
        self.vertices.delete();
        self.textures.delete();
        self.size = 0;
    }
};

pub fn init() !void {
    if (was_init)
        return;

    var vs = try shader.compileFromResource(.vertex, try res.loadResource("shaders/chunk-segments.glsl.vert"));
    defer vs.delete();

    var fs = try shader.compileFromResource(.fragment, try res.loadResource("shaders/chunk-segments.glsl.frag"));
    defer fs.delete();

    chunk_quad_program = try shader.initProgram(&[_]zgl.Shader{ vs, fs });

    prepareChunkIndices();

    was_init = true;
}

pub fn deinit() void {
    if (!was_init)
        return;

    chunk_quad_program.delete();
}

/// 0 -- 2
/// |    |
/// 1 -- 3
///
fn prepareChunkIndices() void {
    chunk_far_quad_indices = zgl.createBuffer();
    chunk_far_quad_indices.bind(.element_array_buffer);
    zgl.bufferStorage(
        .element_array_buffer,
        u16,
        chunk_far_quad_indices_count * gfx.elements_per_quad_face,
        null,
        .{ .map_write = true },
    );

    var buf = @as(*align(64) [chunk_far_quad_indices_count * gfx.elements_per_quad_face]u16, @alignCast(
        @ptrCast(zgl.mapBufferRange(
            .element_array_buffer,
            u16,
            0,
            chunk_far_quad_indices_count * gfx.elements_per_quad_face,
            .{ .write = true },
        )),
    ));

    var i: u16 = 0;
    while (i < chunk_far_quad_indices_count) : (i += 1) {
        const offset = i * gfx.elements_per_quad_face;

        buf[offset + 0] = 0 + offset;
        buf[offset + 1] = 1 + offset;
        buf[offset + 2] = 2 + offset;
        buf[offset + 3] = 1 + offset;
        buf[offset + 4] = 3 + offset;
        buf[offset + 5] = 2 + offset;
    }

    if (!zgl.unmapBuffer(.element_array_buffer))
        @panic("Unmap failed");
}
