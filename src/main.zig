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
    Unexpected,
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

pub const enable_tracy = options.trace;

var tracy_allocator = if (enable_tracy) shared.tracy.TracyAllocator(null).init(&gpa.allocator) else {};

const log = std.log.scoped(.main);

pub fn main() MainReturnValue {
    const main_z = shared.tracy.traceNamed(@src(), "main");
    shared.tracy.frameMark();

    defer {
        if (is_debug_or_test) {
            _ = gpa.deinit();
        }
        main_z.end();
    }

    const allocator = if (enable_tracy) &tracy_allocator.allocator else &gpa.allocator;

    var argument_info = ArgumentInfo.fetch(allocator) catch |err| {
        if (is_debug_or_test) return err;
        return 1;
    };
    defer argument_info.deinit(allocator);

    const io_buffers_z = shared.tracy.traceNamed(@src(), "io buffers");
    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    io_buffers_z.end();

    const result = subcommands.execute(
        allocator,
        &argument_info.arg_iter,
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
            error.UnableToParseArguments => std.io.getStdErr().writeAll("ERROR: unable to parse arguments\n") catch {},
        }

        if (is_debug_or_test) return err;
        return 1;
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    if (result == 0) {
        const flush_z = shared.tracy.traceNamed(@src(), "stdout flush");
        defer flush_z.end();

        log.debug("flushing stdout buffer on successful execution", .{});
        std_out_buffered.flush() catch |err| std.debug.panic("failed to flush stdout: {s}", .{@errorName(err)});
    }
    return result;
}

const ArgumentInfo = struct {
    basename: []const u8,
    exe_path: [:0]const u8,
    arg_iter: std.process.ArgIterator,

    pub fn fetch(allocator: *std.mem.Allocator) !ArgumentInfo {
        const z = shared.tracy.traceNamed(@src(), "fetch argument info");
        defer z.end();

        var arg_iter = try std.process.argsWithAllocator(allocator);

        const exe_path = if (builtin.os.tag == .windows)
            try (arg_iter.next(allocator) orelse @panic("no arguments"))
        else
            arg_iter.nextPosix() orelse @panic("no arguments");
        const basename = std.fs.path.basename(exe_path);
        log.debug("got exe_path: \"{s}\" with basename: \"{s}\"", .{ exe_path, basename });

        return ArgumentInfo{
            .basename = basename,
            .exe_path = exe_path,
            .arg_iter = arg_iter,
        };
    }

    pub fn deinit(self: *ArgumentInfo, allocator: *std.mem.Allocator) void {
        if (builtin.os.tag == .windows) allocator.free(self.exe_path);
        self.arg_iter.deinit();
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
