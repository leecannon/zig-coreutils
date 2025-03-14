// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub fn main() if (shared.is_debug_or_test) subcommands.ExecuteError!u8 else u8 {
    // this causes the frame to start with our main instead of `std.start`
    tracy.frameMark(null);
    const main_z: tracy.Zone = .begin(.{ .src = @src(), .name = "main" });
    defer main_z.end();

    const static = struct {
        var debug_allocator: if (shared.is_debug_or_test) std.heap.DebugAllocator(.{}) else void =
            if (shared.is_debug_or_test) .init else {};
        var tracy_allocator: if (options.trace) tracy.Allocator else void =
            if (options.trace) undefined else {};
    };
    defer {
        if (shared.is_debug_or_test) _ = static.debug_allocator.deinit();
    }

    const allocator = blk: {
        const gpa_allocator = if (shared.is_debug_or_test)
            static.debug_allocator.allocator()
        else
            std.heap.smp_allocator;

        if (options.trace) {
            static.tracy_allocator = .{ .parent = gpa_allocator };
            break :blk static.tracy_allocator.allocator();
        } else {
            break :blk gpa_allocator;
        }
    };

    var argument_info = ArgumentInfo.fetch();

    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());

    const stderr_writer = std.io.getStdErr().writer();
    const io = .{
        .stderr = stderr_writer,
        .stdin = std_in_buffered.reader(),
        .stdout = std_out_buffered.writer(),
    };

    subcommands.execute(
        allocator,
        &argument_info.arg_iter,
        io,
        argument_info.basename,
        std.fs.cwd(),
        argument_info.exe_path,
    ) catch |err| {
        switch (err) {
            error.NoSubcommand => {
                blk: {
                    stderr_writer.writeByte('\'') catch break :blk;
                    stderr_writer.writeAll(argument_info.basename) catch break :blk;
                    stderr_writer.writeAll("' subcommand not found\n") catch break :blk;
                }
                // this error only occurs in one place, no need to print error return trace
                return 1;
            },
            error.OutOfMemory => stderr_writer.writeAll("out of memory\n") catch {},
            error.UnableToParseArguments => stderr_writer.writeAll("unable to parse arguments\n") catch {},
            error.AlreadyHandled => {},
        }

        if (shared.is_debug_or_test) return err;
        return 1;
    };

    // Only flush stdout if the command completed successfully
    // If we flush stdout after printing an error then the error message will not be the last thing printed
    const flush_z: tracy.Zone = .begin(.{ .src = @src(), .name = "stdout flush" });
    defer flush_z.end();

    std_out_buffered.flush() catch |err| {
        shared.unableToWriteTo("stdout", io, err) catch {};
        return 1;
    };

    return 0;
}

const ArgumentInfo = struct {
    basename: []const u8,
    exe_path: [:0]const u8,
    arg_iter: std.process.ArgIterator,

    pub fn fetch() ArgumentInfo {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "fetch argument info" });
        defer z.end();

        var arg_iter = std.process.args();

        const exe_path = arg_iter.next() orelse unreachable;
        const basename = std.fs.path.basename(exe_path);
        log.debug("got exe_path: \"{s}\" with basename: \"{s}\"", .{ exe_path, basename });

        return .{
            .basename = basename,
            .exe_path = exe_path,
            .arg_iter = arg_iter,
        };
    }
};

const builtin = @import("builtin");
const log = std.log.scoped(.main);
const options = @import("options");
const shared = @import("shared.zig");
const std = @import("std");
const subcommands = @import("subcommands.zig");
const tracy = @import("tracy");

pub const tracy_impl = @import("tracy_impl");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
