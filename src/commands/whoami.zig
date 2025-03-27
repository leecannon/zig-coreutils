// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Is this command enabled for the current target?
pub const enabled: bool = shared.target_os == .linux;

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

        _ = try args.nextWithHelpOrVersion(true);

        const euid = system.getEffectiveUserId();

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

        var passwd_file_iter = shared.passwdFileIterator(mapped_passwd_file.file_contents);

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

    test "whoami" {
        const passwd_contents =
            \\root:x:0:0::/root:/usr/bin/bash
            \\daemon:x:1:1::/:/usr/sbin/nologin
            \\bin:x:2:2::/:/usr/sbin/nologin
            \\sys:x:3:3::/:/usr/sbin/nologin
            \\user:x:1001:1001:A User:/home/user:/usr/bin/zsh
            \\
        ;

        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        const etc_dir = try fs_description.root.addDirectory("etc");
        _ = try etc_dir.addFile("passwd", passwd_contents);

        var stdout: std.ArrayList(u8) = .init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(&.{}, .{
            .stdout = stdout.writer().any(),
            .system_description = .{
                .file_system = fs_description,
                .user_group = .{
                    .effective_user_id = 1001,
                },
            },
        });

        try std.testing.expectEqualStrings("user\n", stdout.items);
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.whoami);

const std = @import("std");
const tracy = @import("tracy");
