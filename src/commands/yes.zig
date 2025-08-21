// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const enabled: bool = true;

pub const command: Command = .{
    .name = "yes",

    .short_help =
    \\Usage: {NAME} [STRING]...
    \\   or: {NAME} OPTION
    \\
    \\Repeatedly output a line with all specified STRING(s), or 'y'.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
    ,

    .execute = impl.execute,
};

// namespace required to prevent tests of disabled commands from being analyzed
const impl = struct {
    fn execute(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        system: System,
        exe_path: []const u8,
    ) Command.Error!void {
        _ = exe_path;
        _ = system;

        const string = try getString(allocator, args);
        defer if (shared.free_on_close) string.deinit(allocator);

        if (@import("builtin").is_test) {
            // to allow this command to be tested

            for (0..10) |_| {
                try io.stdoutWriteAll(string.value);
            }

            return;
        }

        while (true) {
            try io.stdoutWriteAll(string.value);
        }

        unreachable;
    }

    fn getString(allocator: std.mem.Allocator, args: *Arg.Iterator) !shared.MaybeAllocatedString {
        var buffer: std.Io.Writer.Allocating = .init(allocator);
        defer if (shared.free_on_close) buffer.deinit();

        const writer = &buffer.writer;

        if (try args.nextWithHelpOrVersion(true)) |arg| {
            writer.writeAll(arg.raw) catch return error.OutOfMemory;
        } else {
            return .not_allocated("y\n");
        }

        while (args.nextRaw()) |arg| {
            writer.writeByte(' ') catch return error.OutOfMemory;
            writer.writeAll(arg) catch return error.OutOfMemory;
        }

        writer.writeByte('\n') catch return error.OutOfMemory;

        return .allocated(buffer.toOwnedSlice() catch return error.OutOfMemory);
    }

    test "yes help" {
        try command.testHelp(true);
    }

    test "yes version" {
        try command.testVersion();
    }

    const lines_to_output_during_tests = 10;

    test "yes no args" {
        var stdout: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(&.{}, .{ .stdout = &stdout.writer });

        const expected = blk: {
            const line = "y\n";

            var expected: std.Io.Writer.Allocating = try .initCapacity(
                std.testing.allocator,
                lines_to_output_during_tests * line.len,
            );
            errdefer expected.deinit();

            try expected.writer.splatBytesAll(line, lines_to_output_during_tests);

            break :blk try expected.toOwnedSlice();
        };
        defer std.testing.allocator.free(expected);

        try std.testing.expectEqualStrings(expected, stdout.written());
    }

    test "yes with args" {
        var stdout: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(
            &.{ "arg1", "arg2" },
            .{ .stdout = &stdout.writer },
        );

        const expected = blk: {
            const line = "arg1 arg2\n";

            var expected: std.Io.Writer.Allocating = try .initCapacity(
                std.testing.allocator,
                lines_to_output_during_tests * line.len,
            );
            errdefer expected.deinit();

            try expected.writer.splatBytesAll(line, lines_to_output_during_tests);

            break :blk try expected.toOwnedSlice();
        };
        defer std.testing.allocator.free(expected);

        try std.testing.expectEqualStrings(expected, stdout.written());
    }

    test "yes fuzz" {
        try command.testFuzz(.{
            .expect_stdout_output_on_success = true,
        });
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const std = @import("std");
