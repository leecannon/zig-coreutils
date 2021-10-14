const std = @import("std");
const subcommands = @import("subcommands.zig");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
const main_return_value = if (is_debug_or_test)
    subcommands.ExecuteError!u8
else
    u8;

var allocator_backing = if (is_debug_or_test)
    std.heap.GeneralPurposeAllocator(.{}){}
else
    std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub fn main() main_return_value {
    defer {
        if (is_debug_or_test) {
            _ = allocator_backing.deinit();
        }
    }

    const allocator = &allocator_backing.allocator;

    var arg_iter = std.process.args();

    const exe_path = (arg_iter.next(allocator) orelse unreachable) catch unreachable;
    defer allocator.free(exe_path);

    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());

    const basename = std.fs.path.basename(exe_path);
    const result = subcommands.executeSubcommand(
        .{
            .allocator = allocator,
            .exe_path = exe_path,
            .basename = basename,
            .arg_iter = &arg_iter,
            .std_err = std.io.getStdErr().writer(),
            .std_in = std_in_buffered.reader(),
            .std_out = std_out_buffered.writer(),
        },
    ) catch |err| {
        switch (err) {
            error.NoSubcommand => std.io.getStdErr().writer().print("ERROR: {s} subcommand not found\n", .{basename}) catch {},
            error.OutOfMemory => std.io.getStdErr().writeAll("ERROR: out of memory\n") catch {},
            error.FailedToParseArguments => std.io.getStdErr().writeAll("ERROR: unexpected error while parsing arguments\n") catch {},
            error.HelpOrVersion => {
                std_out_buffered.flush() catch {};
                return 0;
            },
        }

        if (is_debug_or_test) return err;
        return 1;
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    if (result == 0) std_out_buffered.flush() catch {};
    return result;
}

comptime {
    std.testing.refAllDecls(@This());
}
