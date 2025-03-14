// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

// TODO: How do we test this without introducing the amount of complexity that https://github.com/leecannon/zsw does?
// https://github.com/leecannon/zig-coreutils/issues/1

pub const name = "whoami";

pub const short_help =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Print the user name for the current effective user id.
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

    _ = exe_path;

    _ = try args.nextWithHelpOrVersion(true);

    const euid = std.os.linux.geteuid();

    const passwd_file = try shared.mapFile(@This(), allocator, io, cwd, "/etc/passwd");
    defer passwd_file.close();

    var passwd_file_iter = shared.passwdFileIterator(passwd_file.file_contents);

    while (try passwd_file_iter.next(@This(), io)) |entry| {
        const user_id = std.fmt.parseUnsigned(std.posix.uid_t, entry.user_id, 10) catch
            return shared.printError(
                @This(),
                io,
                "format of '/etc/passwd' is invalid",
            );

        if (user_id != euid) {
            log.debug("found non-matching user id: {}", .{user_id});
            continue;
        }

        log.debug("found matching user id: {}", .{user_id});

        io.stdout.print("{s}\n", .{entry.user_name}) catch |err|
            return shared.unableToWriteTo(
                "stdout",
                io,
                err,
            );

        return;
    }

    return shared.printError(
        @This(),
        io,
        "'/etc/passwd' does not contain the current effective uid",
    );
}

test "whoami help" {
    try shared.testHelp(@This(), true);
}

test "whoami version" {
    try shared.testVersion(@This());
}

const log = std.log.scoped(.whoami);
const shared = @import("../shared.zig");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
