const std = @import("std");
const subcommands = @import("subcommands.zig");
const shared = @import("shared.zig");
const options = @import("options");
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

pub const ENABLE_TRACY = options.trace;
pub const EMIT_CALLSTACK = true;

var tracy_allocator = if (ENABLE_TRACY) shared.trace.TracyAllocator(null).init(&gpa.allocator) else {};

const log = std.log.scoped(.main);

pub fn main() MainReturnValue {
    const z = shared.trace.begin(@src());
    shared.trace.frameMark();

    defer {
        if (is_debug_or_test) {
            _ = gpa.deinit();
        }
        z.end();
    }

    const allocator = if (ENABLE_TRACY) &tracy_allocator.allocator else &gpa.allocator;

    const argument_info = ArgumentInfo.fetch(allocator) catch |err| {
        if (is_debug_or_test) return err;
        return 1;
    };
    defer argument_info.deinit(allocator);

    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());

    const result = subcommands.executeSubcommand(
        allocator,
        argument_info.arguments,
        .{
            .stderr = std.io.getStdErr().writer(),
            .stdin = std_in_buffered.reader(),
            .stdout = std_out_buffered.writer(),
        },
        argument_info.basename,
        argument_info.exe_path,
    ) catch |err| {
        switch (err) {
            error.NoSubcommand => std.io.getStdErr().writer().print("ERROR: {s} subcommand not found\n", .{argument_info.basename}) catch {},
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

const ArgumentInfo = struct {
    basename: []const u8,
    exe_path: []const u8,
    arguments: []const []const u8,

    raw_args: []const [:0]u8,

    pub fn fetch(allocator: *std.mem.Allocator) !ArgumentInfo {
        const z = shared.trace.begin(@src());
        defer z.end();

        const arg_z = shared.trace.beginNamed(@src(), "argsAlloc");
        errdefer arg_z.end();

        const arguments = std.process.argsAlloc(allocator) catch |err| {
            std.io.getStdErr().writer().print("ERROR: unable to access arguments: {s}\n", .{@errorName(err)}) catch {};
            return err;
        };

        arg_z.end();

        const exe_path = arguments[0];
        const basename = std.fs.path.basename(exe_path);
        log.debug("got exe_path: \"{s}\" with basename: \"{s}\"", .{ exe_path, basename });

        return ArgumentInfo{
            .basename = basename,
            .exe_path = exe_path,
            .arguments = arguments[1..],
            .raw_args = arguments,
        };
    }

    pub fn deinit(self: ArgumentInfo, allocator: *std.mem.Allocator) void {
        std.process.argsFree(allocator, self.raw_args);
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
