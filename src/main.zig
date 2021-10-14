const std = @import("std");
const Context = @import("Context.zig");
const subcommands = @import("subcommands.zig");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
const main_return_value = if (is_debug_or_test)
    (error{
        NoSubcommand,
        Overflow,
        InvalidCmdLine,
    } ||
        subcommands.Error)!u8
else
    u8;

pub fn main() main_return_value {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const args = std.process.argsAlloc(&arena.allocator) catch |err| {
        switch (err) {
            error.Overflow => unreachable,
            error.OutOfMemory => std.io.getStdErr().writeAll("ERROR: out of memory\n") catch {},
            error.InvalidCmdLine => std.io.getStdErr().writeAll("ERROR: invalid command line encoding\n") catch {},
        }

        if (is_debug_or_test) return err;
        return 1;
    };

    var context = Context{
        .allocator = &arena.allocator,
        .args = args[1..],
        .exe_path = args[0],
        .err = std.io.getStdErr().writer(),
        .std_in_buffered = Context.BufferedReader{ .unbuffered_reader = std.io.getStdIn().reader() },
        .std_out_buffered = Context.BufferedWriter{ .unbuffered_writer = std.io.getStdOut().writer() },
    };

    const basename = std.fs.path.basename(context.exe_path);
    const result = subcommands.executeSubcommand(&context, basename) catch |err| {
        switch (err) {
            error.NoSubcommand => std.io.getStdErr().writer().print("ERROR: {s} subcommand not found\n", .{basename}) catch {},
            error.OutOfMemory => std.io.getStdErr().writeAll("ERROR: out of memory\n") catch {},
            error.HelpOrVersion => {
                context.flushStdOut();
                return 0;
            },
        }

        if (is_debug_or_test) return err;
        return 1;
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    if (result == 0) context.flushStdOut();
    return result;
}

comptime {
    std.testing.refAllDecls(@This());
}
