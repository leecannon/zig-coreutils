const std = @import("std");
const Context = @import("Context.zig");
const subcommands = @import("subcommands.zig");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
const main_return_value = if (is_debug_or_test)
    (error{NoSubcommand} || subcommands.Error)!u8
else
    u8;

pub fn main() main_return_value {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    // const args = std.process.argsAlloc(&arena.allocator) catch |err| {
    //     switch (err) {
    //         error.Overflow => unreachable,
    //         error.OutOfMemory => std.io.getStdErr().writeAll("ERROR: out of memory\n") catch {},
    //         error.InvalidCmdLine => std.io.getStdErr().writeAll("ERROR: invalid command line encoding\n") catch {},
    //     }

    //     if (is_debug_or_test) return err;
    //     return 1;
    // };

    var arg_iter = std.process.args();

    const exe_path = (arg_iter.next(allocator) orelse unreachable) catch unreachable;
    defer allocator.free(exe_path);

    var context = Context{
        .allocator = allocator,
        .exe_path = exe_path,
        .err = std.io.getStdErr().writer(),
        .std_in_buffered = Context.BufferedReader{ .unbuffered_reader = std.io.getStdIn().reader() },
        .std_out_buffered = Context.BufferedWriter{ .unbuffered_writer = std.io.getStdOut().writer() },
    };

    const basename = std.fs.path.basename(exe_path);
    const result = subcommands.executeSubcommand(&context, basename, &arg_iter) catch |err| switch (err) {
        error.HelpOrVersion => {
            context.flushStdOut();
            return 0;
        },
        error.FailedToParseArguments => {
            // this error is emitted in the argument parsing code
            return 1;
        },
        else => |narrow_err| {
            switch (narrow_err) {
                error.NoSubcommand => std.io.getStdErr().writer().print("ERROR: {s} subcommand not found\n", .{basename}) catch {},
                error.OutOfMemory => std.io.getStdErr().writeAll("ERROR: out of memory\n") catch {},
            }

            if (is_debug_or_test) return narrow_err;
            return 1;
        },
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    if (result == 0) context.flushStdOut();
    return result;
}

comptime {
    std.testing.refAllDecls(@This());
}
