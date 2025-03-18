// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

// TODO: How do we test this without introducing the amount of complexity that https://github.com/leecannon/zsw does?
// https://github.com/leecannon/zig-coreutils/issues/7

pub const command: Command = .{
    .name = "whoami",

    .short_help =
    \\Usage: {NAME} [ignored command line arguments]
    \\   or: {NAME} OPTION
    \\
    \\Print the user name for the current effective user id.
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

    _ = exe_path;

    _ = try args.nextWithHelpOrVersion(true);

    const euid = std.os.linux.geteuid();

    const passwd_file = try shared.mapFile(command, allocator, io, cwd, "/etc/passwd");
    defer passwd_file.close();

    var passwd_file_iter = shared.passwdFileIterator(passwd_file.file_contents);

    while (try passwd_file_iter.next(command, io)) |entry| {
        const user_id = std.fmt.parseUnsigned(std.posix.uid_t, entry.user_id, 10) catch
            return command.printError(
                io,
                "format of '/etc/passwd' is invalid",
            );

        if (user_id != euid) {
            log.debug("found non-matching user id: {}", .{user_id});
            continue;
        }

        try io.stdoutWriteAll(entry.user_name);
        try io.stdoutWriteByte('\n');

        return;
    }

    return command.printError(
        io,
        "'/etc/passwd' does not contain the current effective uid",
    );
}

test "whoami help" {
    try command.testHelp(true);
}

test "whoami version" {
    try command.testVersion();
}

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.whoami);

const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
