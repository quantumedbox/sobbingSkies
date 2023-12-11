const std = @import("std");

// todo: Have path preserved.

// todo: Watchable resource.
const Type = enum {
    static,
    dynamic,
};

/// Dual resource, - could be embedded or runtime loaded depending on compilation options.
pub const Resource = union(Type) {
    static: []const u8,
    dynamic: struct {
        allocator: std.mem.Allocator,
        memory: []const u8,
    },

    pub fn initStatic(memory: []const u8) @This() {
        return @This(){ .static = memory };
    }

    pub fn initDynamic(memory: []const u8, allocator: std.mem.Allocator) @This() {
        return @This(){ .dynamic = .{
            .memory = memory,
            .allocator = allocator,
        } };
    }

    pub fn getData(self: @This()) []const u8 {
        return switch (self) {
            .static => |v| v,
            .dynamic => |v| v.memory,
        };
    }

    pub fn free(self: @This()) void {
        switch (self) {
            .static => {},
            .dynamic => |v| v.allocator.free(v.memory),
        }
    }

    pub fn load(comptime path: []const u8) !@This() {
        if (comptime std.meta.globalOption("embed_resources", bool) orelse false) {
            return initStatic(@embedFile(path));
        } else {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();
            var dir = try resourceDir();
            defer dir.close();
            const file = try dir.openFile(path, .{});
            defer file.close();
            const memory = try file.readToEndAlloc(allocator, std.math.maxInt(u24));
            return initDynamic(memory, allocator);
        }
    }
};

// todo: Settle on something better.
fn resourceDir() !std.fs.Dir {
    // todo: Cache it?
    return try std.fs.cwd().openDir("src", .{});
}
