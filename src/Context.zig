const std = @import("std");
const builtin = @import("builtin");
const Subcommand = @import("subcommands.zig").Subcommand;

const Context = @This();

allocator: *std.mem.Allocator,
arg_iter: *std.process.ArgIterator,

exe_path: [:0]const u8 = undefined,

std_err: std.fs.File,
std_in: std.fs.File,
std_out: std.fs.File,

std_in_buffered: ?BufferedReader = null,
std_out_buffered: ?BufferedWriter = null,

pub const BufferedWriter = std.io.BufferedWriter(std.mem.page_size, std.fs.File.Writer);
pub const BufferedReader = std.io.BufferedReader(std.mem.page_size, std.fs.File.Reader);

pub fn bufferedStdIn(self: *Context) BufferedReader {
    if (self.std_in_buffered == null) {
        self.std_in_buffered = BufferedReader{ .unbuffered_reader = self.std_in.reader() };
    }
    return self.std_in_buffered.?;
}

pub fn bufferedStdOut(self: *Context) BufferedWriter {
    if (self.std_out_buffered == null) {
        self.std_out_buffered = BufferedWriter{ .unbuffered_writer = self.std_out.writer() };
    }
    return self.std_out_buffered.?;
}

const is_windows = builtin.os.tag == .windows;

pub inline fn getNextArg(context: *Context) !?[:0]const u8 {
    if (is_windows) {
        if (context.arg_iter.next(context.allocator)) |arg_or_err| {
            if (arg_or_err) |arg| {
                return arg;
            } else |err| {
                switch (err) {
                    error.OutOfMemory => {
                        // this is displayed to the user in main
                    },
                    error.InvalidCmdLine => {
                        // TODO: print error
                    },
                }
                return err;
            }
        }
        return null;
    }
    return context.arg_iter.nextPosix();
}

pub fn checkForHelpOrVersion(context: *Context, comptime subcommand: Subcommand) !?[:0]const u8 {
    const arg = (try context.getNextArg()) orelse return null;

    if (arg.len >= 2) {
        if (arg[0] == '-') {
            if (arg[1] == '-') {
                if (std.mem.eql(u8, arg[2..], "help")) {
                    context.std_out.writer().print(subcommand.usage, .{context.exe_path}) catch {};
                    return error.HelpOrVersion;
                }
                if (std.mem.eql(u8, arg[2..], "version")) {
                    context.printVersion(subcommand);
                    return error.HelpOrVersion;
                }
            } else {
                if (std.mem.eql(u8, arg[1..], "h")) {
                    context.std_out.writer().print(subcommand.usage, .{context.exe_path}) catch {};
                    return error.HelpOrVersion;
                }
            }
        }
    }

    return arg;
}

fn printVersion(context: Context, subcommand: Subcommand) void {
    context.std_out.writer().print(
        \\{s} (zig-coreutils) 0.0.1
        \\MIT License Copyright (c) 2021 Lee Cannon
        \\
    , .{subcommand.name}) catch return;
}

comptime {
    std.testing.refAllDecls(@This());
}
