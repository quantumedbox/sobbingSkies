//! This ring buffer stores read and write indices while being able to utilise
//! the full backing slice by incrementing the indices modulo twice the slice's
//! length and reducing indices modulo the slice's length on slice access. This
//! means that whether the ring buffer is full or empty can be distinguished by
//! looking at the difference between the read and write indices without adding
//! an extra boolean flag or having to reserve a slot in the buffer.
//!
//! This ring buffer has not been implemented with thread safety in mind, and
//! therefore should not be assumed to be suitable for use cases involving
//! separate reader and writer threads.
//!
//! Pulled from 0.11.0-stable zig std and extended to align more with ArrayList.

// todo: Automatically resize in non-assumption methods.
// todo: A way to shrink capacity.

const mem = @import("std").mem;
const Allocator = mem.Allocator;
const assert = @import("std").debug.assert;
const testing = @import("std").testing;

pub fn RingBuffer(comptime T: type) type {
    return struct {
        items: []T,
        read_index: usize = 0,
        write_index: usize = 0,
        allocator: Allocator,

        pub const Error = error{Full};

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .items = &[_]T{},
                .allocator = allocator,
            };
        }

        /// Allocate a new `RingBuffer`; `deinit()` should be called to free the buffer.
        pub fn initCapacity(allocator: Allocator, capacity: usize) Allocator.Error!@This() {
            var self = @This().init(allocator);
            try self.ensureTotalCapacity(capacity);
            return self;
        }

        /// Free the items backing a `RingBuffer`; must be passed the same `Allocator` as
        /// `init()`.
        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.items);
            self.* = undefined;
        }

        /// Modify the array so that it can hold at least `new_capacity` items.
        /// Invalidates pointers if additional memory is needed.
        pub fn ensureTotalCapacity(self: *@This(), new_capacity: usize) Allocator.Error!void {
            if (self.items.len >= new_capacity) return;

            var better_capacity = self.items.len;
            while (true) {
                better_capacity +|= better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }

            const old_memory = self.items;
            if (!self.allocator.resize(self.items, better_capacity)) {
                // todo: Don't copy before hand, specialize it in future copying.
                const new_memory = try self.allocator.alloc(T, new_capacity);
                @memcpy(new_memory[0..self.items.len], old_memory);
                self.allocator.free(old_memory);
                self.items = new_memory;
            }

            const length = self.len();

            if (self.mask(self.write_index) >= self.mask(self.read_index))
                mem.copy(T, self.items[0..length], self.items[self.mask(self.read_index) .. self.mask(self.read_index) + length])
            else {
                const from_read_to_end = self.mask(self.items.len - self.read_index);
                @memcpy(
                    self.items[from_read_to_end .. from_read_to_end + length - from_read_to_end],
                    self.items[0..self.mask(self.write_index)],
                );
                @memcpy(
                    self.items[0..from_read_to_end],
                    self.items[self.mask(self.read_index) .. self.mask(self.read_index) + from_read_to_end],
                );
            }

            self.write_index = length;
            self.read_index = 0;
        }

        /// Returns `index` modulo the length of the backing slice.
        fn mask(self: @This(), index: usize) usize {
            return index % self.items.len;
        }

        /// Returns `index` modulo twice the length of the backing slice.
        fn mask2(self: @This(), index: usize) usize {
            return index % (2 * self.items.len);
        }

        /// Write `item` into the ring buffer. Returns `error.Full` if the ring
        /// buffer is full.
        pub fn write(self: *@This(), item: T) Error!void {
            if (self.isFull()) return error.Full;
            self.writeAssumeCapacity(item);
        }

        /// Write `item` into the ring buffer. If the ring buffer is full, the
        /// oldest item is overwritten.
        pub fn writeAssumeCapacity(self: *@This(), item: T) void {
            self.items[self.mask(self.write_index)] = item;
            self.write_index = self.mask2(self.write_index + 1);
        }

        /// Write `items` into the ring buffer. Returns `error.Full` if the ring
        /// buffer does not have enough space, without writing any items.
        pub fn writeSlice(self: *@This(), items: []const T) Error!void {
            if (self.len() + items.len > self.items.len) return error.Full;
            self.writeSliceAssumeCapacity(items);
        }

        /// Write `items` into the ring buffer. If there is not enough space, older
        /// items will be overwritten.
        pub fn writeSliceAssumeCapacity(self: *@This(), items: []const T) void {
            for (items) |b| self.writeAssumeCapacity(b);
        }

        /// Consume a item from the ring buffer and return it. Returns `null` if the
        /// ring buffer is empty.
        pub fn read(self: *@This()) ?T {
            if (self.isEmpty()) return null;
            return self.readAssumeLength();
        }

        /// Consume a item from the ring buffer and return it; asserts that the buffer
        /// is not empty.
        pub fn readAssumeLength(self: *@This()) T {
            assert(!self.isEmpty());
            const item = self.items[self.mask(self.read_index)];
            self.read_index = self.mask2(self.read_index + 1);
            return item;
        }

        /// Returns `true` if the ring buffer is empty and `false` otherwise.
        pub fn isEmpty(self: @This()) bool {
            return self.write_index == self.read_index;
        }

        /// Returns `true` if the ring buffer is full and `false` otherwise.
        pub fn isFull(self: @This()) bool {
            return self.mask2(self.write_index + self.items.len) == self.read_index;
        }

        /// Returns the length
        pub fn len(self: @This()) usize {
            const wrap_offset = 2 * self.items.len * @intFromBool(self.write_index < self.read_index);
            const adjusted_write_index = self.write_index + wrap_offset;
            return adjusted_write_index - self.read_index;
        }

        /// A `Slice` represents a region of a ring buffer. The region is split into two
        /// sections as the ring buffer items will not be contiguous if the desired
        /// region wraps to the start of the backing slice.
        pub const Slice = struct {
            first: []T,
            second: []T,
        };

        /// Returns a `Slice` for the region of the ring buffer starting at
        /// `self.mask(start_unmasked)` with the specified length.
        pub fn sliceAt(self: @This(), start_unmasked: usize, length: usize) Slice {
            assert(length <= self.items.len);
            const slice1_start = self.mask(start_unmasked);
            const slice1_end = @min(self.items.len, slice1_start + length);
            const slice1 = self.items[slice1_start..slice1_end];
            const slice2 = self.items[0 .. length - slice1.len];
            return Slice{
                .first = slice1,
                .second = slice2,
            };
        }

        /// Returns a `Slice` for the last `length` items written to the ring buffer.
        /// Does not check that any items have been written into the region.
        pub fn sliceLast(self: @This(), length: usize) Slice {
            return self.sliceAt(self.write_index + self.items.len - length, length);
        }
    };
}

test "collection.RingBuffer.initCapacity" {
    var ring = try RingBuffer(i32).initCapacity(testing.allocator, 8);
    defer ring.deinit();
    try testing.expect(ring.items.len == 8);
}

test "collection.RingBuffer.ensureTotalCapacity" {
    var ring = try RingBuffer(i32).initCapacity(testing.allocator, 8);
    defer ring.deinit();
    try ring.ensureTotalCapacity(16);
    try testing.expect(ring.items.len == 16);

    try ring.ensureTotalCapacity(0);
    try testing.expect(ring.items.len == 16);
}

test "collection.RingBuffer.write+read" {
    var ring = try RingBuffer(usize).initCapacity(testing.allocator, 8);
    defer ring.deinit();
    try ring.write(20);
    try testing.expect(ring.read().? == 20);

    for (0..7) |i|
        try ring.write(i);
    for (0..7) |_|
        _ = ring.read().?;
}

test "collection.RingBuffer.writeSlice+read" {
    var ring = try RingBuffer(i32).initCapacity(testing.allocator, 8);
    defer ring.deinit();

    const input = &[_]i32{ 0, 1, 2, 3, 4, 5, 6, 7 };

    {
        try ring.writeSlice(input);
        var output: [8]i32 = undefined;
        for (output[0..8]) |*item|
            item.* = ring.read().?;
        try testing.expectEqualSlices(i32, input, &output);
    }

    {
        try ring.writeSlice(input);
        var output: [8]i32 = undefined;
        for (output[0..8]) |*item|
            item.* = ring.read().?;
        try testing.expectEqualSlices(i32, input, &output);
    }
}

test "collection.RingBuffer.writeSlice+read+ensureTotalCapacity" {
    var ring = try RingBuffer(i32).initCapacity(testing.allocator, 8);
    defer ring.deinit();

    const input = &[_]i32{ 0, 1, 2, 3, 4, 5, 6, 7 };

    try ring.writeSlice(input);
    try ring.ensureTotalCapacity(16);
    try ring.writeSlice(input);

    {
        var output: [8]i32 = undefined;
        for (output[0..8]) |*item|
            item.* = ring.read().?;
        try testing.expectEqualSlices(i32, input, &output);
        for (output[0..8]) |*item|
            item.* = ring.read().?;
        try testing.expectEqualSlices(i32, input, &output);
    }
}
