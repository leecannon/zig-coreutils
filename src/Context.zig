const std = @import("std");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const subcommands = @import("subcommands.zig");

const Context = @This();

allocator: *std.mem.Allocator,

exe_path: [:0]const u8,

err: std.fs.File.Writer,

std_in_buffered: BufferedReader,
std_out_buffered: BufferedWriter,

pub fn int(self: *Context) BufferedReader.Reader {
    return self.std_in_buffered.reader();
}

pub fn out(self: *Context) BufferedWriter.Writer {
    return self.std_out_buffered.writer();
}

pub fn flushStdOut(self: *Context) void {
    self.std_out_buffered.flush() catch @panic("failed to flush to standard out");
}

pub const BufferedWriter = std.io.BufferedWriter(std.mem.page_size, std.fs.File.Writer);
pub const BufferedReader = std.io.BufferedReader(std.mem.page_size, std.fs.File.Reader);

pub fn printVersion(self: *Context, name: []const u8) void {
    self.out().print(
        \\{s} (zig-coreutils) 0.0.1
        \\MIT License Copyright (c) 2021 Lee Cannon
        \\
    , .{name}) catch return;
}

comptime {
    std.testing.refAllDecls(@This());
}
