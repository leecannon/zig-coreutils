// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "false";

pub const short_help =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Exit with a status code indicating failure.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

pub fn execute(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) shared.CommandError!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
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
        shared.testExecute(
            @This(),
            &.{},
            .{},
        ),
    );
}

test "false ignores args" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try std.testing.expectError(
        error.AlreadyHandled,
        shared.testExecute(
            @This(),
            &.{ "these", "arguments", "are", "ignored" },
            .{},
        ),
    );

    try std.testing.expectEqualStrings("", stdout.items);
}

test "false help" {
    try shared.testHelp(@This(), true);
}

test "false version" {
    try shared.testVersion(@This());
}

const log = std.log.scoped(.false);
const shared = @import("../shared.zig");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
