//! Abstraction over graphical buffer that provides optimal attribute allocations,
//! while simplifying use with shaders.

// todo: Abstract over textures too?
// todo: When used for indices calculate the range.
// todo: When caching is used we can save effected subranges to then push,
//       which could reduce memory congestion.

const std = @import("std");
const zgl = @import("zgl");
const Attribute = @import("Attribute.zig");

pub const max_descriptors = 8;

descriptors: [max_descriptors]Attribute.Descriptor,
attribute_meta: [max_descriptors]AttributeMeta,

len: usize,

/// Denotes whether buffer should respect 4 byte alignment for attributes or pack them tightly.
is_packed: bool,

is_resizable: bool,

server_buffer: zgl.Buffer,

client_buffer: []u8,

/// Whether memory is duplicated in client.
is_cached: bool,

/// Optional allocator for client side duplication used for staging.
allocator: ?std.mem.Allocator,

const Self = @This();

const AttributeMeta = struct {
    offset: usize,
    stride: usize,
};

pub fn init(descriptors: []const Attribute.Descriptor, options: struct {
    is_packed: bool = false,
    is_interleaved: bool = true,
    is_resizable: bool = true,
    preallocate_len: usize = 0,
}) Self {
    std.debug.assert(descriptors.len <= max_descriptors);
    std.debug.assert(options.is_resizable or options.preallocate_len > 0);

    var sorted_descriptors_array: [max_descriptors]Attribute.Descriptor = undefined;
    var sorted_descriptors = sorted_descriptors_array[0..descriptors.len];
    @memcpy(sorted_descriptors, descriptors);

    // todo: This is suboptimal, consider case like: (floatx3, uint32x1, floatx2)
    const S = struct {
        fn orderDescriptors(context: void, lhs: Attribute.Descriptor, rhs: Attribute.Descriptor) bool {
            _ = context;
            return rhs.alignment() <= lhs.alignment();
        }
    };

    std.sort.heap(Attribute.Descriptor, sorted_descriptors, {}, S.orderDescriptors);
    std.debug.print("{any}\n", .{sorted_descriptors});

    var result: Self = .{};
    _ = result;
}

/// Mappable graphical memory for one single attribute.
pub const View = struct {
    descriptor: *Attribute.Descriptor,
    buffer: zgl.Buffer,
    meta: AttributeMeta,
};
