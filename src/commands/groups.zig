// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Is this command enabled for the current target?
pub const enabled: bool = switch (shared.target_os) {
    .linux, .macos => true,
    .windows => false,
};

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

        const opt_arg = try args.nextWithHelpOrVersion(true);

        const mapped_passwd_file = blk: {
            const passwd_file = system.cwd().openFile("/etc/passwd", .{}) catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to open '/etc/passwd': {s}",
                    .{@errorName(err)},
                );
            errdefer if (shared.free_on_close) passwd_file.close();

            const stat = passwd_file.stat() catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to stat '/etc/passwd': {s}",
                    .{@errorName(err)},
                );

            break :blk passwd_file.mapReadonly(stat.size) catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to map '/etc/passwd': {s}",
                    .{@errorName(err)},
                );
        };
        defer if (shared.free_on_close) mapped_passwd_file.close();

        return if (opt_arg) |arg|
            namedUser(allocator, io, arg.raw, mapped_passwd_file.file_contents, system)
        else
            currentUser(allocator, io, mapped_passwd_file.file_contents, system);
    }

    fn currentUser(
        allocator: std.mem.Allocator,
        io: IO,
        passwd_file_contents: []const u8,
        system: System,
    ) Command.Error!void {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "current user" });
        defer z.end();

        const euid = system.getEffectiveUserId();

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

            return printGroups(allocator, entry.user_name, primary_group_id, io, system);
        }

        return command.printError(
            io,
            "'/etc/passwd' does not contain the current effective uid",
        );
    }

    fn namedUser(
        allocator: std.mem.Allocator,
        io: IO,
        user: []const u8,
        passwd_file_contents: []const u8,
        system: System,
    ) Command.Error!void {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "namedUser" });
        defer z.end();
        z.text(user);

        log.debug("namedUser called, user='{s}'", .{user});

        var passwd_file_iter = shared.passwdFileIterator(passwd_file_contents);

        while (try passwd_file_iter.next(command, io)) |entry| {
            if (!std.mem.eql(u8, entry.user_name, user)) {
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

            return printGroups(allocator, entry.user_name, primary_group_id, io, system);
        }

        return command.printErrorAlloc(allocator, io, "unknown user '{s}'", .{user});
    }

    fn printGroups(
        allocator: std.mem.Allocator,
        user: []const u8,
        primary_group_id: std.posix.uid_t,
        io: IO,
        system: System,
    ) !void {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print groups" });
        defer z.end();
        z.text(user);

        log.debug(
            "printGroups called, user='{s}', primary_group_id={}",
            .{ user, primary_group_id },
        );

        const mapped_group_file = blk: {
            const group_file = system.cwd().openFile("/etc/group", .{}) catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to open '/etc/group': {s}",
                    .{@errorName(err)},
                );
            errdefer if (shared.free_on_close) group_file.close();

            const stat = group_file.stat() catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to stat '/etc/group': {s}",
                    .{@errorName(err)},
                );

            break :blk group_file.mapReadonly(stat.size) catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to map '/etc/group': {s}",
                    .{@errorName(err)},
                );
        };
        defer if (shared.free_on_close) mapped_group_file.close();

        var group_file_iter = shared.groupFileIterator(mapped_group_file.file_contents);

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
                if (!std.mem.eql(u8, member, user)) continue;

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

    test "groups" {
        const passwd_contents =
            \\root:x:0:0::/root:/usr/bin/bash
            \\daemon:x:1:1::/:/usr/sbin/nologin
            \\bin:x:2:2::/:/usr/sbin/nologin
            \\sys:x:3:3::/:/usr/sbin/nologin
            \\user:x:1001:1001:A User:/home/user:/usr/bin/zsh
            \\
        ;

        const group_contents =
            \\root:x:0:
            \\daemon:x:1:
            \\bin:x:2:
            \\sys:x:3:user
            \\user:x:1001:
            \\wheel:x:10:user
            \\
        ;

        const file_system: *System.TestBackend.Description.FileSystemDescription = try .create(std.testing.allocator);
        defer file_system.destroy();

        const etc_dir = try file_system.root.addDirectory("etc");
        _ = try etc_dir.addFile("passwd", passwd_contents);
        _ = try etc_dir.addFile("group", group_contents);

        var stdout: std.ArrayList(u8) = .init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(&.{}, .{
            .stdout = stdout.writer().any(),
            .system_description = .{
                .file_system = file_system,
                .user_group = .{
                    .effective_user_id = 1001,
                },
            },
        });

        try std.testing.expectEqualStrings("sys user wheel\n", stdout.items);
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.groups);

const std = @import("std");
const tracy = @import("tracy");
