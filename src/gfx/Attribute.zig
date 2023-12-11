const zgl = @import("zgl");
const vec = @import("primitives").vec;
const meta = @import("meta");
const AttributeStorage = @import("AttributeStorage.zig");

pub const Descriptor = struct {
    primitive: Primitive,
    arity: usize,
    is_normalized: bool,

    /// Must duplicate location symbol in shader.
    name: []const u8,

    usage: enum {
        constant,
        mutating,
    },

    pub const Primitive = enum {
        float32,
        uint8,
        uint16,
        texture,

        pub fn from(comptime T: type) @This() {
            if (T == zgl.Texture) return .texture;
            return switch (@typeInfo(T)) {
                .Float => |float| brk: {
                    if (float.bit_count != 32) @panic("unsupported");
                    break :brk .float32;
                },
                .Int => |int| brk: {
                    if (int.signedness == .unisgned) {
                        break :brk switch (int.bit_count) {
                            8 => .uint8,
                            16 => .uint16,
                            else => @panic("unsupported"),
                        };
                    } else @panic("unsupported");
                },
            };
        }
    };

    pub fn size(self: @This()) usize {
        return switch (self.primitive) {
            .float => 4 * self.arity,
            .uint8 => 1 * self.arity,
            .uint16 => 2 * self.arity,
            .texture => 4 * self.arity,
        };
    }

    pub fn alignment(self: @This()) usize {
        return self.size();
    }

    pub fn from(comptime T: type, name: []const u8, options: struct {
        is_normalized: bool = true,
        usage: @TypeOf(Descriptor.usage) = .mutating,
    }) Self {
        return switch (@typeInfo(T)) {
            .Struct => brk: {
                if (!meta.isTypeIdenitityMatching(T, vec.vector_type_identity))
                    @panic("unsupported struct");
                break :brk .{
                    .primitive = Primitive.from(T.Item),
                    .arity = T.artity,
                    .is_normalized = options.is_normalized,
                    .name = name,
                    .usage = options.usage,
                };
            },
            else => .{
                .primitive = Primitive.from(T),
                .arity = 1,
                .is_normalized = options.is_normalized,
                .name = name,
                .usage = options.usage,
            },
        };
    }
};

pub const Distribution = enum { per_vertex, per_instance, uniformed };

descriptor: Descriptor,
distribution: Distribution,

payload: union {
    value: *anyopaque,
    view: AttributeStorage.View,
},

const Self = @This();
