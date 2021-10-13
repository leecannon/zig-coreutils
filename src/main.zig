const std = @import("std");
const Context = @import("Context.zig");
const subcommands = @import("subcommands.zig");
const builtin = @import("builtin");

const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
const main_return_value = if (is_debug_or_test)
    (error{
        NoSubcommand,
    } ||
        subcommands.Subcommand.Error)!u8
else
    u8;

pub fn main() main_return_value {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var arg_iter = std.process.args();

    var context = Context{
        .allocator = &arena.allocator,
        .arg_iter = &arg_iter,
        .std_err = std.io.getStdErr(),
        .std_in = std.io.getStdIn(),
        .std_out = std.io.getStdOut(),
    };

    const name = (context.getNextArg() catch |err| {
        if (is_debug_or_test) return err;
        return 1;
    }) orelse unreachable;

    return subcommands.executeSubcommand(&context, std.fs.path.basename(name)) catch |err| {
        switch (err) {
            error.NoSubcommand => {
                // TODO: print error
            },
            error.OutOfMemory => {
                // TODO: print error
            },
            error.InvalidCmdLine => {
                // this is displayed to the user at the occurance of the error
            },
        }

        if (is_debug_or_test) return err;
        return 1;
    };
}

comptime {
    std.testing.refAllDecls(@This());
}
