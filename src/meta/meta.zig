//! Used to distinguish types produced by functions.

const std = @import("std");

pub const Resource = @import("resource.zig").Resource;
pub const CodeThread = @import("code-thread.zig").CodeThread;

pub fn isTypeIdenitityMatching(comptime T: type, comptime identity: []const u8) bool {
    if (std.meta.activeTag(@typeInfo(T)) != .Struct or !@hasDecl(T, "type_identity")) return false;
    return std.mem.eql(u8, T.type_identity, identity);
}
