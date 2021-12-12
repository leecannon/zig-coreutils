const std = @import("std");
const subcommands = @import("subcommands.zig");
const shared = @import("shared.zig");
const options = @import("options");
const builtin = @import("builtin");
const zsw = @import("zsw");

pub const enable_tracy = options.trace;
pub const tracy_enable_callstack = true;

const log = std.log.scoped(.main);

var allocator_backing = if (!shared.is_debug_or_test) std.heap.ArenaAllocator.init(std.heap.page_allocator) else {};
var gpa = if (shared.is_debug_or_test)
    std.heap.GeneralPurposeAllocator(.{}){}
else
    std.heap.stackFallback(std.mem.page_size, allocator_backing.allocator());

pub fn main() if (shared.is_debug_or_test) subcommands.ExecuteError!u8 else u8 {
    const main_z = shared.tracy.traceNamed(@src(), "main");
    // this causes the frame to start with our main instead of `std.start`
    shared.tracy.frameMark();

    defer {
        if (shared.is_debug_or_test) {
            _ = gpa.deinit();
        }
        main_z.end();
    }

    const gpa_allocator: std.mem.Allocator = if (shared.is_debug_or_test) gpa.allocator() else gpa.get();
    var tracy_allocator = if (enable_tracy) shared.tracy.TracyAllocator(null).init(gpa_allocator) else {};
    const allocator = if (enable_tracy) tracy_allocator.allocator() else gpa_allocator;

    var argument_info = ArgumentInfo.fetch();

    const io_buffers_z = shared.tracy.traceNamed(@src(), "io buffers");
    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    io_buffers_z.end();

    const stderr_writer = std.io.getStdErr().writer();
    const io = .{
        .stderr = stderr_writer,
        .stdin = std_in_buffered.reader(),
        .stdout = std_out_buffered.writer(),
    };

    const result = subcommands.execute(
        allocator,
        &argument_info.arg_iter,
        io,
        argument_info.basename,
        zsw.host_system,
        argument_info.exe_path,
    ) catch |err| {
        switch (err) {
            error.NoSubcommand => blk: {
                stderr_writer.writeByte('\'') catch break :blk;
                stderr_writer.writeAll(argument_info.basename) catch break :blk;
                stderr_writer.writeAll("' subcommand not found\n") catch break :blk;
            },
            error.OutOfMemory => stderr_writer.writeAll("out of memory\n") catch {},
            error.UnableToParseArguments => stderr_writer.writeAll("unable to parse arguments\n") catch {},
        }

        if (shared.is_debug_or_test) return err;
        return 1;
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    if (result == 0) {
        const flush_z = shared.tracy.traceNamed(@src(), "stdout flush");
        defer flush_z.end();

        log.debug("flushing stdout buffer on successful execution", .{});
        std_out_buffered.flush() catch |err| {
            shared.unableToWriteTo("stdout", io, err);
            return 1;
        };
    }
    return result;
}

const ArgumentInfo = struct {
    basename: []const u8,
    exe_path: [:0]const u8,
    arg_iter: std.process.ArgIterator,

    pub fn fetch() ArgumentInfo {
        const z = shared.tracy.traceNamed(@src(), "fetch argument info");
        defer z.end();

        var arg_iter = std.process.args();

        const exe_path = arg_iter.nextPosix() orelse unreachable;
        const basename = std.fs.path.basename(exe_path);
        log.debug("got exe_path: \"{s}\" with basename: \"{s}\"", .{ exe_path, basename });

        return ArgumentInfo{
            .basename = basename,
            .exe_path = exe_path,
            .arg_iter = arg_iter,
        };
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
