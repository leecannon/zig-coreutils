// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "yes";

pub const short_help =
    \\Usage: {0s} [STRING]...
    \\   or: {0s} OPTION
    \\
    \\Repeatedly output a line with all specified STRING(s), or 'y'.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `yes`
pub const extended_help = "";

pub fn execute(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
    defer z.end();

    _ = exe_path;
    _ = cwd;

    const string = try getString(allocator, args);
    defer if (shared.free_on_close) string.deinit(allocator);

    while (true) {
        io.stdout.writeAll(string.value) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
    }
}

fn getString(allocator: std.mem.Allocator, args: *shared.ArgIterator) !shared.MaybeAllocatedString {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
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
    try subcommands.testHelp(@This(), true);
}

test "yes version" {
    try subcommands.testVersion(@This());
}

const log = std.log.scoped(.yes);
const shared = @import("../shared.zig");
const std = @import("std");
const subcommands = @import("../subcommands.zig");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
