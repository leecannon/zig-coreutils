// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

// TODO: How do we test this without introducing the amount of complexity that https://github.com/leecannon/zsw does?
// https://github.com/leecannon/zig-coreutils/issues/1

pub const command: Command = .{
    .name = "groups",

    .short_help =
    \\Usage: {NAME} [user]
    \\   or: {NAME} OPTION
    \\
    \\Display the current group names. 
    \\The optional [user] parameter will display the groups for the named user.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
    ,

    .extended_help =
    \\Examples:
    \\  groups
    \\  groups username
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

    const opt_arg = try args.nextWithHelpOrVersion(true);

    const passwd_file = try shared.mapFile(command, allocator, io, cwd, "/etc/passwd");
    defer passwd_file.close();

    return if (opt_arg) |arg|
        otherUser(allocator, io, arg, passwd_file.file_contents, cwd)
    else
        currentUser(allocator, io, passwd_file.file_contents, cwd);
}

fn currentUser(
    allocator: std.mem.Allocator,
    io: IO,
    passwd_file_contents: []const u8,
    cwd: std.fs.Dir,
) Command.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "current user" });
    defer z.end();

    const euid = std.os.linux.geteuid();

    log.debug("currentUser called, euid: {}", .{euid});

    var passwd_file_iter = shared.passwdFileIterator(passwd_file_contents);

    while (try passwd_file_iter.next(command, io)) |entry| {
        const user_id = std.fmt.parseUnsigned(
            std.posix.uid_t,
            entry.user_id,
            10,
        ) catch
            return command.printError(
                io,
                "format of '/etc/passwd' is invalid",
            );

        if (user_id != euid) {
            log.debug("found non-matching user id: {}", .{user_id});
            continue;
        }

        log.debug("found matching user id: {}", .{user_id});

        const primary_group_id = std.fmt.parseUnsigned(
            std.posix.uid_t,
            entry.primary_group_id,
            10,
        ) catch
            return command.printError(
                io,
                "format of '/etc/passwd' is invalid",
            );

        return printGroups(allocator, entry.user_name, primary_group_id, io, cwd);
    }

    return command.printError(
        io,
        "'/etc/passwd' does not contain the current effective uid",
    );
}

fn otherUser(
    allocator: std.mem.Allocator,
    io: IO,
    arg: Arg,
    passwd_file_contents: []const u8,
    cwd: std.fs.Dir,
) Command.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "other user" });
    defer z.end();
    z.text(arg.raw);

    log.debug("otherUser called, arg='{s}'", .{arg.raw});

    var passwd_file_iter = shared.passwdFileIterator(passwd_file_contents);

    while (try passwd_file_iter.next(command, io)) |entry| {
        if (!std.mem.eql(u8, entry.user_name, arg.raw)) {
            log.debug("found non-matching user: {s}", .{entry.user_name});
            continue;
        }

        log.debug("found matching user: {s}", .{entry.user_name});

        const primary_group_id = std.fmt.parseUnsigned(
            std.posix.uid_t,
            entry.primary_group_id,
            10,
        ) catch
            return command.printError(
                io,
                "format of '/etc/passwd' is invalid",
            );

        return printGroups(allocator, entry.user_name, primary_group_id, io, cwd);
    }

    return command.printErrorAlloc(allocator, io, "unknown user {s}", .{arg.raw});
}

fn printGroups(
    allocator: std.mem.Allocator,
    user_name: []const u8,
    primary_group_id: std.posix.uid_t,
    io: IO,
    cwd: std.fs.Dir,
) !void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print groups" });
    defer z.end();
    z.text(user_name);

    log.debug(
        "printGroups called, user_name='{s}', primary_group_id={}",
        .{ user_name, primary_group_id },
    );

    const group_file = try shared.mapFile(command, allocator, io, cwd, "/etc/group");
    defer group_file.close();

    var group_file_iter = shared.groupFileIterator(group_file.file_contents);

    var first = true;

    while (try group_file_iter.next(command, io)) |entry| {
        const group_id = std.fmt.parseUnsigned(std.posix.uid_t, entry.group_id, 10) catch
            return command.printError(
                io,
                "format of '/etc/group' is invalid",
            );

        if (group_id == primary_group_id) {
            if (!first) {
                try io.stdoutWriteByte(' ');
            }
            try io.stdoutWriteAll(entry.group_name);

            first = false;
            continue;
        }

        var member_iter = entry.iterateMembers();
        while (member_iter.next()) |member| {
            if (!std.mem.eql(u8, member, user_name)) continue;

            if (!first) {
                try io.stdoutWriteByte(' ');
            }

            try io.stdoutWriteAll(entry.group_name);
            first = false;
            break;
        }
    }

    try io.stdoutWriteByte('\n');
}

test "groups help" {
    try command.testHelp(true);
}

test "groups version" {
    try command.testVersion();
}

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.groups);

const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
