// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "true";

pub const short_help =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Exit with a status code indicating success.
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
}

test "true no args" {
    try shared.testExecute(
        @This(),
        &.{},
        .{},
    );
}

test "true ignores args" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try shared.testExecute(
        @This(),
        &.{
            "these", "arguments", "are", "ignored",
        },
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings("", stdout.items);
}

test "true help" {
    try shared.testHelp(@This(), true);
}

test "true version" {
    try shared.testVersion(@This());
}

const log = std.log.scoped(.true);
const shared = @import("../shared.zig");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
