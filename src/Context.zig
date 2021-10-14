const std = @import("std");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const Subcommand = @import("subcommands.zig").Subcommand;

const Context = @This();

allocator: *std.mem.Allocator,

args: []const [:0]const u8,
arg_index: usize = 0,

exe_path: [:0]const u8,

err: std.fs.File.Writer,

std_in_buffered: BufferedReader,
in: BufferedReader.Reader,

std_out_buffered: BufferedWriter,
out: BufferedWriter.Writer,

pub fn init(
    allocator: *std.mem.Allocator,
    args: []const [:0]const u8,
    exe_path: [:0]const u8,
    std_err_file: std.fs.File,
    std_in_file: std.fs.File,
    std_out_file: std.fs.File,
) Context {
    var context = Context{
        .allocator = allocator,
        .args = args,
        .exe_path = exe_path,
        .err = std_err_file.writer(),
        .std_in_buffered = BufferedReader{ .unbuffered_reader = std_in_file.reader() },
        .in = undefined,
        .std_out_buffered = BufferedWriter{ .unbuffered_writer = std_out_file.writer() },
        .out = undefined,
    };

    context.in = context.std_in_buffered.reader();
    context.out = context.std_out_buffered.writer();

    return context;
}

pub fn flushStdOut(self: *Context) void {
    self.std_out_buffered.flush() catch @panic("failed to flush to standard out");
}

pub const BufferedWriter = std.io.BufferedWriter(std.mem.page_size, std.fs.File.Writer);
pub const BufferedReader = std.io.BufferedReader(std.mem.page_size, std.fs.File.Reader);

pub fn getNextArg(self: *Context) ?[:0]const u8 {
    if (self.arg_index < self.args.len) {
        const arg = self.args[self.arg_index];
        self.arg_index += 1;
        return arg;
    }
    return null;
}

pub fn checkForHelpOrVersion(self: *Context, comptime subcommand: Subcommand) !?[:0]const u8 {
    const arg = self.getNextArg() orelse return null;

    if (arg.len >= 2) {
        if (arg[0] == '-') {
            if (arg[1] == '-') {
                if (std.mem.eql(u8, arg[2..], "help")) {
                    self.out.print(subcommand.usage, .{self.exe_path}) catch {};
                    return error.HelpOrVersion;
                }
                if (std.mem.eql(u8, arg[2..], "version")) {
                    self.printVersion(subcommand);
                    return error.HelpOrVersion;
                }
            } else {
                if (std.mem.eql(u8, arg[1..], "h")) {
                    self.out.print(subcommand.usage, .{self.exe_path}) catch {};
                    return error.HelpOrVersion;
                }
            }
        }
    }

    return arg;
}

fn printVersion(self: *Context, subcommand: Subcommand) void {
    self.out.print(
        \\{s} (zig-coreutils) 0.0.1
        \\MIT License Copyright (c) 2021 Lee Cannon
        \\
    , .{subcommand.name}) catch return;
}

comptime {
    std.testing.refAllDecls(@This());
}
