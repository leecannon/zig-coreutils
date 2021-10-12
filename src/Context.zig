const std = @import("std");

allocator: *std.mem.Allocator,
arg_iter: *std.process.ArgIterator,

std_err: std.fs.File.Writer,
std_in: std.fs.File.Writer,
std_out: std.fs.File.Writer,

comptime {
    std.testing.refAllDecls(@This());
}
