const std = @import("std");
const zgl = @import("zgl");

/// Manages GPU side allocations with ability to grow buffer in-place.
// note: Any used memory should not be overwritten unless requested, as with DMA
//       it will create synchronization, as likely buffer is being used in render.
// todo: Keep info about which pages are still in use to prevent synchronization on page merging / rewriting after free.
//       This will allow for double buffering with less footprint.
//
// todo: Use GL_MAP_PERSISTENT_BIT
//
pub const BufferHeap = struct {
    buffer: zgl.Buffer,
    allocator: std.mem.Allocator,

    pages: std.ArrayList(Page),
    /// Back references to pages that aren't in use.
    free_pages: std.DynamicBitSet,

    /// Bytes allocated, including padding.
    size: usize,
    /// Unused bytes at the end.
    free: usize,

    // todo: Collect info about padding in pages, helpful heuristics for defragmentation.
    // total_padding: usize,

    /// By how much every allocation grows and shrinks.
    granularity: usize,

    pub const Index = usize;
    /// Each allocation is aligned to this.
    const alignment = 4;

    const Page = struct {
        /// Byte offset.
        offset: usize,
        /// Size in bytes, in active use.
        size: usize,
        /// Bytes owned by page, but not in active use.
        padding: usize,
    };

    const Configuration = struct {
        granularity: usize = 8192,
    };

    pub fn init(allocator: std.mem.Allocator, configuration: Configuration) !BufferHeap {
        std.debug.assert(std.mem.isAligned(configuration.granularity, alignment));

        const buffer = zgl.createBuffer();
        errdefer buffer.delete();

        const pages = std.ArrayList(Page).init(allocator);
        errdefer pages.deinit();

        const free_pages = try std.DynamicBitSet.initEmpty(allocator, 0);
        errdefer free_pages.deinit();

        return BufferHeap{
            .allocator = allocator,
            .buffer = buffer,
            .size = 0,
            .free = 0,
            .pages = pages,
            .free_pages = free_pages,
            .granularity = configuration.granularity,
        };
    }

    // todo: Use some other binding point to conflict less?
    /// Must be called before using, note that it affects buffer bindings.
    pub fn bind(self: BufferHeap) void {
        self.buffer.bind(.array_buffer);
    }

    pub fn free(self: BufferHeap) void {
        zgl.deleteBuffer(self.buffer);
        self.pages.deinit();
        self.free_pages.deinit();
    }

    // todo: Procedure to merge consequent free pages.

    // todo: Modification over single buffer mapping might be more driver friendly,
    //       current way assumes map and unmap for each modification.
    fn writeAndFlush(comptime T: type, offset: usize, items: []const T) void {
        var buf = @as([]align(64) T, @alignCast(zgl.mapBufferRange(.array_buffer, T, offset, items.len, .{
            .write = true,
            .invalidate_range = true,
            .unsynchronized = true,
            // .flush_explicit = true,
        })));
        std.mem.copy(T, buf, items);
        // todo: Should retry.
        if (!zgl.unmapBuffer(.array_buffer))
            @panic("Unmap failed");
    }

    // todo: Accept slice of memories, which helps optimize for bulk allocations.
    pub fn allocate(self: *BufferHeap, comptime T: type, items: []const T) std.mem.Allocator.Error!Index {
        const size = items.len * @sizeOf(@TypeOf(items));
        const padding = std.mem.alignForward(usize, size, alignment) - size;

        // Try using pages that are marked as free.
        // for (self.free_pages.items, 0..) |p, i| {
        //     const page = &self.pages.items[p];
        //     if (page.padding >= memory.len) {
        //         std.debug.assert(page.size == 0);
        //         local.writeAndFlush(page.offset);
        //         page.size = memory.len;
        //         page.padding -= memory.len;
        //         self.free_pages.swapRemove(i);
        //     }
        // }

        // Use allocated space that isn't yet covered by pages.
        // if (self.free >= memory.len) {
        // }

        // New allocation, created in advance, so that fail will not affect gpu state.
        try self.pages.append(Page{
            .offset = self.size,
            .size = size,
            .padding = padding,
        });

        // (Re)Allocate storage.
        if (self.free < size) {
            // todo: GPU side buffer allocation might fail, we might need to handle this case.
            //       One way is to simply create reallocation client side, but roundtrip is slow.
            //       Other alternative is forceful repopulation, signaled to caller.
            self.buffer.bind(.copy_read_buffer);
            const reallocation = zgl.createBuffer();
            reallocation.bind(.array_buffer);
            const allocated = std.mem.alignForward(usize, self.size + self.free + size, self.granularity);
            zgl.bufferStorage(.array_buffer, u8, allocated, null, .{ .map_write = true });
            zgl.copyBufferSubData(.copy_read_buffer, .array_buffer, u8, 0, 0, self.size);
            zgl.invalidateBufferData(self.buffer);
            self.buffer.delete();
            self.buffer = reallocation;
            self.free = allocated - self.size;
        } else {
            // First allocation.
            const allocated = std.mem.alignForward(usize, size, self.granularity);
            zgl.bufferStorage(.array_buffer, u8, allocated, null, .{ .map_write = true });
            self.free = allocated;
        }

        writeAndFlush(self.size, items);
        self.size += size + padding;
        self.free -= size + padding;
        return Index{self.pages.items.len - 1};
    }
};
