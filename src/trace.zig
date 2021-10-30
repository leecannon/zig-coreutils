const std = @import("std");
const root = @import("root");

const ENABLE_TRACY = if (@hasDecl(root, "ENABLE_TRACY")) root.ENABLE_TRACY else false;
const EMIT_CALLSTACK = if (@hasDecl(root, "EMIT_CALLSTACK")) root.EMIT_CALLSTACK else false;
const CALLSTACK_DEPTH = if (@hasDecl(root, "CALLSTACK_DEPTH")) root.CALLSTACK_DEPTH else 20;

const tracy = if (ENABLE_TRACY) @cImport({
    @cDefine("TRACY_ENABLE", "");
    @cInclude("TracyC.h");
}) else struct {
    const ___tracy_c_zone_context = void;
};

pub const Zone = struct {
    c: if (ENABLE_TRACY) tracy.___tracy_c_zone_context else void,

    pub inline fn end(self: Zone) void {
        if (!ENABLE_TRACY) return;
        tracy.___tracy_emit_zone_end(self.c);
    }

    pub inline fn addText(self: Zone, msg: []const u8) void {
        if (!ENABLE_TRACY) return;
        tracy.___tracy_emit_zone_text(self.c, msg.ptr, msg.len);
    }

    pub inline fn setName(self: Zone, msg: []const u8) void {
        if (!ENABLE_TRACY) return;
        tracy.___tracy_emit_zone_name(self.c, msg.ptr, msg.len);
    }

    pub inline fn setColor(self: Zone, color: u32) void {
        if (!ENABLE_TRACY) return;
        tracy.___tracy_emit_zone_color(self.c, color);
    }

    pub inline fn setValue(self: Zone, value: u64) void {
        if (!ENABLE_TRACY) return;
        tracy.___tracy_emit_zone_value(self.c, value);
    }
};

pub inline fn begin(comptime src: std.builtin.SourceLocation) Zone {
    if (!ENABLE_TRACY) return .{ .c = {} };

    if (EMIT_CALLSTACK) {
        return .{
            .c = tracy.___tracy_emit_zone_begin_callstack(&.{
                .name = null,
                .function = src.fn_name.ptr,
                .file = src.file.ptr,
                .line = src.line,
                .color = 0,
            }, CALLSTACK_DEPTH, 1),
        };
    } else {
        return .{
            .c = tracy.___tracy_emit_zone_begin(&.{
                .name = null,
                .function = src.fn_name.ptr,
                .file = src.file.ptr,
                .line = src.line,
                .color = 0,
            }, 1),
        };
    }
}

pub inline fn beginNamed(comptime src: std.builtin.SourceLocation, comptime name: [:0]const u8) Zone {
    if (!ENABLE_TRACY) return .{ .c = {} };

    if (EMIT_CALLSTACK) {
        return .{
            .c = tracy.___tracy_emit_zone_begin_callstack(&.{
                .name = name.ptr,
                .function = src.fn_name.ptr,
                .file = src.file.ptr,
                .line = src.line,
                .color = 0,
            }, CALLSTACK_DEPTH, 1),
        };
    } else {
        return .{
            .c = tracy.___tracy_emit_zone_begin(&.{
                .name = name.ptr,
                .function = src.fn_name.ptr,
                .file = src.file.ptr,
                .line = src.line,
                .color = 0,
            }, 1),
        };
    }
}

pub inline fn plot(comptime name: []const u8, value: f64) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_plot(name.ptr, value);
}

pub inline fn appInfo(data: []const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_message_appinfo(data.ptr, data.len);
}

// This function only accepts comptime known strings, see `messageCopy` for runtime strings
pub inline fn message(comptime msg: [:0]const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_messageL(msg.ptr, if (EMIT_CALLSTACK) CALLSTACK_DEPTH else 0);
}

// This function only accepts comptime known strings, see `messageColorCopy` for runtime strings
pub inline fn messageColor(comptime msg: [:0]const u8, color: u32) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_messageLC(msg.ptr, if (EMIT_CALLSTACK) CALLSTACK_DEPTH else 0, color);
}

pub inline fn messageCopy(msg: []const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_message(msg.ptr, msg.len, if (EMIT_CALLSTACK) CALLSTACK_DEPTH else 0);
}

pub inline fn messageColorCopy(msg: [:0]const u8, color: u32) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_messageC(msg.ptr, msg.len, if (EMIT_CALLSTACK) CALLSTACK_DEPTH else 0, color);
}

pub inline fn setThreadName(comptime msg: [:0]const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_set_thread_name(msg.ptr);
}

pub inline fn frameMark() void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_frame_mark(null);
}

pub inline fn frameMarkNamed(comptime name: [:0]const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_frame_mark(name.ptr);
}

pub inline fn frameMarkStart(comptime name: [:0]const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_frame_mark_start(name.ptr);
}

pub inline fn frameMarkEnd(comptime name: [:0]const u8) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_frame_mark_end(name.ptr);
}

pub inline fn frameImage(image: [*]const u8, width: u32, height: u32, offset: u8, flip: bool) void {
    if (!ENABLE_TRACY) return;
    tracy.___tracy_emit_frame_image(image.ptr, width, height, offset, @boolToInt(flip));
}

inline fn alloc(ptr: [*]u8, len: usize) void {
    if (!ENABLE_TRACY) return;

    if (EMIT_CALLSTACK) {
        tracy.___tracy_emit_memory_alloc(ptr, len, 0);
    } else {
        tracy.___tracy_emit_memory_alloc_callstack(ptr, len, CALLSTACK_DEPTH, 0);
    }
}

inline fn allocNamed(ptr: [*]u8, len: usize, comptime name: [:0]const u8) void {
    if (!ENABLE_TRACY) return;

    if (EMIT_CALLSTACK) {
        tracy.___tracy_emit_memory_alloc_named(ptr, len, 0, name.ptr);
    } else {
        tracy.___tracy_emit_memory_alloc_callstack_named(ptr, len, CALLSTACK_DEPTH, 0, name.ptr);
    }
}

inline fn free(ptr: [*]u8) void {
    if (!ENABLE_TRACY) return;

    if (EMIT_CALLSTACK) {
        tracy.___tracy_emit_memory_free(ptr, 0);
    } else {
        tracy.___tracy_emit_memory_free_callstack(ptr, CALLSTACK_DEPTH, 0);
    }
}

inline fn freeNamed(ptr: [*]u8, comptime name: [:0]const u8) void {
    if (!ENABLE_TRACY) return;

    if (EMIT_CALLSTACK) {
        tracy.___tracy_emit_memory_free_named(ptr, 0, name.ptr);
    } else {
        tracy.___tracy_emit_memory_free_callstack_named(ptr, CALLSTACK_DEPTH, 0, name.ptr);
    }
}

pub fn TracyAllocator(comptime name: ?[:0]const u8) type {
    return struct {
        allocator: std.mem.Allocator,
        parent_allocator: *std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator) Self {
            return .{
                .parent_allocator = allocator,
                .allocator = .{
                    .allocFn = allocFn,
                    .resizeFn = resizeFn,
                },
            };
        }

        fn allocFn(allocator: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) std.mem.Allocator.Error![]u8 {
            const self = @fieldParentPtr(Self, "allocator", allocator);
            const result = self.parent_allocator.allocFn(self.parent_allocator, len, ptr_align, len_align, ret_addr);
            if (result) |data| {
                if (name) |n| {
                    allocNamed(data.ptr, data.len, n);
                } else {
                    alloc(data.ptr, data.len);
                }
            } else |_| {
                message("allocation failed");
            }
            return result;
        }

        fn resizeFn(allocator: *std.mem.Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) std.mem.Allocator.Error!usize {
            const self = @fieldParentPtr(Self, "allocator", allocator);

            if (self.parent_allocator.resizeFn(self.parent_allocator, buf, buf_align, new_len, len_align, ret_addr)) |resized_len| {
                if (name) |n| {
                    freeNamed(buf.ptr, n);
                } else {
                    free(buf.ptr);
                }

                if (new_len == 0) {
                    // this was a shrink or a resize
                    if (name) |n| {
                        allocNamed(buf.ptr, resized_len, n);
                    } else {
                        alloc(buf.ptr, resized_len);
                    }
                }

                return resized_len;
            } else |err| {
                message("allocation resize failed");
                return err;
            }
        }
    };
}

comptime {
    std.testing.refAllDecls(@This());
}
