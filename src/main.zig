const std = @import("std");
const subcommands = @import("subcommands.zig");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;

const MainErrorSet = error{
    Overflow,
    InvalidCmdLine,
} || subcommands.ExecuteError;

const MainReturnValue = if (is_debug_or_test)
    MainErrorSet!u8
else
    u8;

var allocator_backing = if (!is_debug_or_test) std.heap.ArenaAllocator.init(std.heap.page_allocator) else {};
var gpa = if (is_debug_or_test)
    std.heap.GeneralPurposeAllocator(.{}){}
else
    std.heap.stackFallback(std.mem.page_size, &allocator_backing.allocator);

const log = std.log.scoped(.main);

pub fn main() MainReturnValue {
    defer {
        if (is_debug_or_test) {
            _ = gpa.deinit();
        }
    }

    const allocator = &gpa.allocator;

    const arguments = std.process.argsAlloc(allocator) catch |err| {
        std.io.getStdErr().writer().print("ERROR: unable to access arguments: {s}\n", .{@errorName(err)}) catch {};
        if (is_debug_or_test) return err;
        return 1;
    };
    defer std.process.argsFree(allocator, arguments);

    const exe_path = arguments[0];
    const basename = std.fs.path.basename(exe_path);
    log.debug("got exe_path: \"{s}\" with basename: \"{s}\"", .{ exe_path, basename });

    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());

    const result = subcommands.executeSubcommand(
        allocator,
        arguments[1..],
        .{
            .stderr = std.io.getStdErr().writer(),
            .stdin = std_in_buffered.reader(),
            .stdout = std_out_buffered.writer(),
        },
        basename,
        exe_path,
    ) catch |err| {
        switch (err) {
            error.NoSubcommand => std.io.getStdErr().writer().print("ERROR: {s} subcommand not found\n", .{basename}) catch {},
            error.OutOfMemory => std.io.getStdErr().writeAll("ERROR: out of memory\n") catch {},
        }

        if (is_debug_or_test) return err;
        return 1;
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    if (result == 0) {
        log.debug("flushing stdout buffer on successful execution", .{});
        std_out_buffered.flush() catch |err| std.debug.panic("failed to flush stdout: {s}", .{@errorName(err)});
    }
    return result;
}

comptime {
    std.testing.refAllDecls(@This());
}
