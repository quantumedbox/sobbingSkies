//! Based on: https://www.cs.umd.edu/class/spring2020/cmsc754/Lects/lect13-delaun-alg.pdf
//! Optimizations involved:
//! - Cached neighbors for traversal.
//! - Minimal memory footprint.
//! - Cached circumferences.
//! - No circumference calculations for new subdivisions, - circumferences of neighbors are used instead.
//! - Lazy circumference calculation, as some places might not be neighboring new subdivisions.
//! - Extensive use of vectorization.
//! - Care given to linear access of memory.

const std = @import("std");

const VertexComponent = f32;
pub const Vertex = @Vector(2, VertexComponent);
const Index = u15;
pub const Rect = @import("primitives").Rect(VertexComponent);
pub const Vector2 = @import("primitives").Vector2;

pub const Builder = struct {
    triangles: std.ArrayList(Triangle),
    vertices: std.ArrayList(Vertex),
    allocator: std.mem.Allocator,

    // todo: init with expected amount of points to preallocate beforehand.
    pub fn init(allocator: std.mem.Allocator, rect: Rect) !@This() {
        var triangles = try std.ArrayList(Triangle).initCapacity(allocator, 2);
        errdefer triangles.deinit();
        var vertices = try std.ArrayList(Vertex).initCapacity(allocator, 4);
        errdefer vertices.deinit();

        try vertices.ensureUnusedCapacity(4);
        try triangles.ensureUnusedCapacity(2);

        for (rect.corners()) |corner|
            vertices.append(Vertex{ corner.x(), corner.y() }) catch unreachable;

        triangles.append(Triangle{
            .points = [3]Index{ 0, 2, 1 },
            .neighbors = [3]?Index{ null, 1, null },
        }) catch unreachable;

        triangles.append(Triangle{
            .points = [3]Index{ 3, 1, 2 },
            .neighbors = [3]?Index{ null, 0, null },
        }) catch unreachable;

        return .{
            .triangles = triangles,
            .vertices = vertices,
            .allocator = allocator,
        };
    }

    pub fn insertAtRandom(self: *@This(), point: Vertex, generator: std.rand.Random) !void {
        // Find a triangle the point lies starting from some random triangle.
        var abc_index: Index = @intCast(generator.int(Index) % self.triangles.items.len);
        var abc = &self.triangles.items[abc_index];

        var relation = abc.pointRelation(self.vertices, point);
        while (relation != .contained) {
            abc_index = abc.neighbors[@intCast(@intFromEnum(relation))].?;
            abc = &self.triangles.items[abc_index];
            relation = abc.pointRelation(self.vertices, point);
        }

        // Allocate two new triangles, as well as new vertex.
        const new_vertex_index: Index = @intCast(self.vertices.items.len);
        try self.vertices.append(point);

        const pbc_index: Index = @intCast(self.triangles.items.len);
        const apc_index: Index = @intCast(self.triangles.items.len + 1);
        try self.triangles.ensureUnusedCapacity(2);

        // Divide the abc triangle into three.

        abc = &self.triangles.items[abc_index];

        // Insert pbc.
        self.triangles.append(Triangle{
            .points = [3]Index{ new_vertex_index, abc.points[1], abc.points[2] },
            .neighbors = [3]?Index{ abc_index, abc.neighbors[1], apc_index },
        }) catch unreachable;

        // Insert apc.
        self.triangles.append(Triangle{
            .points = [3]Index{ abc.points[0], new_vertex_index, abc.points[2] },
            .neighbors = [3]?Index{ abc_index, pbc_index, abc.neighbors[2] },
        }) catch unreachable;

        // Update neighbors to be aware of new triangles.
        inline for (abc.neighbors[1..], [2]Index{ pbc_index, apc_index }) |n, e|
            if (n) |i| {
                const p = &self.triangles.items[i];
                p.neighbors[p.neighborPosition(abc_index)] = e;
            };

        // Existing abc is reused.
        abc.points[2] = new_vertex_index;
        abc.neighbors[1] = pbc_index;
        abc.neighbors[2] = apc_index;
        abc.circumference = null;

        // Recursively adjust edges of triangles so that circumferences are only encasing 3 points at a time.
        // todo: Try inlining initial calls via @call(.always_inline, ...).
        self.trySwapping(abc_index, 0);
        self.trySwapping(pbc_index, 1);
        self.trySwapping(apc_index, 2);
    }

    fn trySwapping(self: @This(), triangle_index: Index, edge: u2) void {
        // First find opposite to edge point that lies in neighbor.
        const triangle = &self.triangles.items[triangle_index];
        const neighbor_index = triangle.neighbors[edge];
        if (neighbor_index == null)
            return;

        const neighbor = &self.triangles.items[neighbor_index.?];

        if (neighbor.circumference == null)
            neighbor.circumference = Triangle.Circumference.init(neighbor.*, self.vertices);

        // Position of neighbor's point opposide to shared with triangle edge.
        const point_order = neighbor.nextAfter(triangle.points[edge]);
        const point_index = neighbor.points[point_order];
        const prev_edge = if (edge == 0) 2 else edge - 1;
        if (neighbor.doesFailIncircleTest(self.vertices.items[triangle.points[prev_edge]])) {
            // Incircle test failed, swap edges of two triangles and then try swapping newly swapped ones.
            const next_edge = (edge + 1) % 3;
            const next_point_order = (point_order + 1) % 3;
            const prev_point_order = if (point_order == 0) 2 else point_order - 1;

            // Update neighbors of triangles in which edge was swapped.
            if (triangle.neighbors[next_edge]) |i| {
                const n = &self.triangles.items[i];
                n.neighbors[n.neighborPosition(triangle_index)] = neighbor_index.?;
            }

            if (neighbor.neighbors[prev_point_order]) |i| {
                const n = &self.triangles.items[i];
                n.neighbors[n.neighborPosition(neighbor_index.?)] = triangle_index;
            }

            const neighbor_prev_point_order_neighbor_index_cache = neighbor.neighbors[prev_point_order];

            neighbor.points[prev_point_order] = triangle.points[prev_edge];
            neighbor.neighbors[next_point_order] = triangle.neighbors[next_edge];
            neighbor.neighbors[prev_point_order] = triangle_index;
            neighbor.circumference = null;

            triangle.points[next_edge] = point_index;
            triangle.neighbors[next_edge] = neighbor_index.?;
            triangle.neighbors[edge] = neighbor_prev_point_order_neighbor_index_cache;
            triangle.circumference = null;

            self.trySwapping(triangle_index, edge);
            self.trySwapping(neighbor_index.?, point_order);
        }
    }
};

const Triangle = struct {
    // References to vertices it's composed of, named abc, in CCW orientation.
    points: [3]Index,

    // References to triangles that are on other side of any edge, if any.
    // Order is: ab, bc, ca
    neighbors: [3]?Index,

    // Lazily calculated and cached for incircle tests.
    circumference: ?Circumference = null,

    pub const Circumference = struct {
        center: Vertex,
        radius_squared: VertexComponent, // todo: Way to get a type capable of holding squared values.

        pub fn init(triangle: Triangle, vertices: std.ArrayList(Vertex)) @This() {
            const a = vertices.items[triangle.points[0]];
            const b = vertices.items[triangle.points[1]];
            const c = vertices.items[triangle.points[2]];

            const ab: Vertex = @splat(magnitudeSquared(a));
            const cd: Vertex = @splat(magnitudeSquared(b));
            const ef: Vertex = @splat(magnitudeSquared(c));

            const cmb = @shuffle(VertexComponent, c - b, undefined, [2]i32{ 1, 0 });
            const amc = @shuffle(VertexComponent, a - c, undefined, [2]i32{ 1, 0 });
            const bma = @shuffle(VertexComponent, b - a, undefined, [2]i32{ 1, 0 });

            const center = ((ab * cmb + cd * amc + ef * bma) / (a * cmb + b * amc + c * bma)) / @as(Vertex, @splat(2));

            return .{
                .center = center,
                .radius_squared = magnitudeSquared(a - center),
            };
        }
    };

    // todo: Try perpendicular dot product approach.
    pub fn pointRelation(self: @This(), vertices: std.ArrayList(Vertex), point: Vertex) enum(u2) {
        outside_ab = 0,
        outside_bc = 1,
        outside_ca = 2,
        contained = 3,
    } {
        const a = vertices.items[self.points[0]];
        const b = vertices.items[self.points[1]];
        const c = vertices.items[self.points[2]];

        // https://stackoverflow.com/questions/1560492/how-to-tell-whether-a-point-is-to-the-right-or-left-side-of-a-line

        const p = point;

        // Calculate cross products for all edges at once.
        const q = @Vector(12, VertexComponent){ b[0], b[1], c[0], c[1], a[0], a[1], p[1], p[0], p[1], p[0], p[1], p[0] };
        const w = @Vector(12, VertexComponent){ a[0], a[1], b[0], b[1], c[0], c[1], a[1], a[0], b[1], b[0], c[1], c[0] };
        const e = q - w;

        const r = @shuffle(VertexComponent, e, undefined, [6]i32{ 0, 1, 2, 3, 4, 5 });
        const t = @shuffle(VertexComponent, e, undefined, [6]i32{ 6, 7, 8, 9, 10, 11 });
        const y = r * t;

        const u = @shuffle(VertexComponent, y, undefined, [3]i32{ 4, 2, 0 });
        const i = @shuffle(VertexComponent, y, undefined, [3]i32{ 5, 3, 1 });
        const o = (u - i) > @Vector(3, VertexComponent){ 0, 0, 0 };

        const mask = @as(u3, @intFromBool(o[2])) << 2 | @as(u3, @intFromBool(o[1])) << 1 | @as(u3, @intFromBool(o[0]));

        return @enumFromInt(@clz(mask));
    }

    pub inline fn doesFailIncircleTest(self: @This(), point: Vertex) bool {
        return magnitudeSquared(self.circumference.?.center - point) < self.circumference.?.radius_squared;
    }

    // todo: Shouldn't be here.
    pub inline fn magnitudeSquared(p: Vertex) VertexComponent {
        return @reduce(.Add, p * p);
    }

    // Finds which point comes after given one, by index, CCW.
    // Used to translate point names when traveling between neighbors.
    pub inline fn nextAfter(self: @This(), point_index: Index) u2 {
        inline for (self.points, 0..) |p, i|
            if (point_index == p)
                return @intCast((i + 1) % 3);
        unreachable;
    }

    pub inline fn neighborPosition(self: @This(), triangle_index: Index) usize {
        inline for (self.neighbors, 0..) |n, i|
            if (triangle_index == n)
                return i;
        unreachable;
    }
};

test "random insertion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    var triangulator = try Builder.init(gpa.allocator(), Rect.init(
        Vector2(VertexComponent).init(.{ -1, -1 }),
        Vector2(VertexComponent).init(.{ 1, 1 }),
    ));

    var prng = std.rand.DefaultPrng.init(123123);
    const rng = prng.random();
    for (0..128) |_| {
        const x = rng.float(VertexComponent) * 2 - 1;
        const y = rng.float(VertexComponent) * 2 - 1;
        try triangulator.insertAtRandom(Vertex{ x, y }, rng);
    }

    // var triangles: [128 * 2 + 2]gfx.triangle.ScreenspaceTriangle = undefined;
    // for (&triangles, triangulator.triangles.items) |*out, in| {
    //     out.a = triangulator.vertices.items[in.points[0]];
    //     out.b = triangulator.vertices.items[in.points[1]];
    //     out.c = triangulator.vertices.items[in.points[2]];
    // }
}
