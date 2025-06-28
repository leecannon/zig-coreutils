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
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = command.name });
        defer z.end();

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
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "get string" });
        defer z.end();

        var buffer = std.ArrayList(u8).init(allocator);
        defer if (shared.free_on_close) buffer.deinit();

        if (try args.nextWithHelpOrVersion(true)) |arg| {
            try buffer.appendSlice(arg.raw);
        } else {
            return .not_allocated("y\n");
        }

        while (args.nextRaw()) |arg| {
            try buffer.append(' ');
            try buffer.appendSlice(arg);
        }

        try buffer.append('\n');

        return .allocated(try buffer.toOwnedSlice());
    }

    test "yes help" {
        try command.testHelp(true);
    }

    test "yes version" {
        try command.testVersion();
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
const tracy = @import("tracy");
