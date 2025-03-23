// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Is this command enabled for the current target?
pub const enabled: bool = true;

pub const command: Command = .{
    .name = "true",

    .short_help =
    \\Usage: {NAME} [ignored command line arguments]
    \\   or: {NAME} OPTION
    \\
    \\Exit with a status code indicating success.
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

        _ = io;
        _ = exe_path;
        _ = system;
        _ = allocator;

        _ = try args.nextWithHelpOrVersion(true);
    }

    test "true no args" {
        try command.testExecute(
            &.{},
            .{},
        );
    }

    test "true ignores args" {
        var stdout = std.ArrayList(u8).init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(
            &.{
                "these", "arguments", "are", "ignored",
            },
            .{ .stdout = stdout.writer().any() },
        );

        try std.testing.expectEqualStrings("", stdout.items);
    }

    test "true help" {
        try command.testHelp(true);
    }

    test "true version" {
        try command.testVersion();
    }

    test "true fuzz" {
        try command.testFuzz(.{ .expect_stdout_output_on_success = false });
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const std = @import("std");
const tracy = @import("tracy");
