// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const command: Command = .{
    .name = "false",

    .short_help =
    \\Usage: {NAME} [ignored command line arguments]
    \\   or: {NAME} OPTION
    \\
    \\Exit with a status code indicating failure.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
    ,

    .execute = execute,
};

fn execute(
    allocator: std.mem.Allocator,
    io: IO,
    args: *Arg.Iterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) Command.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = command.name });
    defer z.end();

    _ = io;
    _ = exe_path;
    _ = cwd;
    _ = allocator;

    _ = try args.nextWithHelpOrVersion(true);

    // FIXME: This is weird, is this acceptable to allow the other shared to not have to worry about u8 return value?
    return error.AlreadyHandled;
}

test "false no args" {
    try std.testing.expectError(
        error.AlreadyHandled,
        command.testExecute(&.{}, .{}),
    );
}

test "false ignores args" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try std.testing.expectError(
        error.AlreadyHandled,
        command.testExecute(
            &.{ "these", "arguments", "are", "ignored" },
            .{},
        ),
    );

    try std.testing.expectEqualStrings("", stdout.items);
}

test "false help" {
    try command.testHelp(true);
}

test "false version" {
    try command.testVersion();
}

test "false fuzz" {
    try command.testFuzz(.{ .expect_stderr_output_on_failure = false });
}

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");

const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
