const std = @import("std");
const builtin = @import("builtin");
const Description = @import("descriptions.zig").Description;

const Context = @This();

allocator: *std.mem.Allocator,
arg_iter: *std.process.ArgIterator,

std_err: std.fs.File.Writer,
std_in: std.fs.File.Writer,
std_out: std.fs.File.Writer,

const is_windows = builtin.os.tag == .windows;

pub inline fn getNextArg(context: Context) ?[:0]const u8 {
    if (is_windows) {
        if (context.arg_iter.next(context.allocator)) |arg_or_err| {
            if (arg_or_err) |arg| {
                return arg;
            } else |err| switch (err) {
                error.OutOfMemory => {
                    // TODO
                    std.os.exit(1);
                },
                error.InvalidCmdLine => {
                    // TODO
                    std.os.exit(1);
                },
            }
        }
        return null;
    }
    return context.arg_iter.nextPosix();
}

pub fn checkForHelpOrVersion(context: Context, description: Description) ?[:0]const u8 {
    const arg = context.getNextArg() orelse return null;

    if (arg.len >= 2) {
        if (arg[0] == '-') {
            if (arg[1] == '-') {
                if (std.mem.eql(u8, arg[2..], "help")) {
                    context.std_out.writeAll(description.usage) catch {};
                    std.os.exit(0);
                }
                if (std.mem.eql(u8, arg[2..], "version")) {
                    context.printVersion(description);
                    std.os.exit(0);
                }
            } else {
                if (std.mem.eql(u8, arg[1..], "h")) {
                    context.std_out.writeAll(description.usage) catch {};
                    std.os.exit(0);
                }
            }
        }
    }

    return arg;
}

fn printVersion(context: Context, description: Description) void {
    context.std_out.print(
        \\{s} (zig-coreutils) 0.0.1
        \\MIT License Copyright (c) 2021 Lee Cannon
        \\
    , .{description.name}) catch return;
}

comptime {
    std.testing.refAllDecls(@This());
}
