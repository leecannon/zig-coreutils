// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Is this command enabled for the current target?
pub const enabled: bool = true;

pub const command: Command = .{
    .name = "unlink",

    .short_help =
    \\Usage: {NAME} FILE...
    \\   or: {NAME} OPTION
    \\
    \\Call the unlink function to remove each FILE.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
    ,

    .extended_help =
    \\Examples:
    \\  unlink FILE
    \\  unlink FILE1 FILE2
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

        var opt_arg: ?Arg = (try args.nextWithHelpOrVersion(true)) orelse
            return command.printInvalidUsage(
                io,
                exe_path,
                "missing file operand",
            );

        var cwd = system.cwd();

        while (opt_arg) |file_arg| : (opt_arg = args.next()) {
            const file_path = file_arg.raw;

            const file_zone: tracy.Zone = .begin(.{ .src = @src(), .name = "unlink file" });
            defer file_zone.end();
            file_zone.text(file_path);

            log.debug("unlinking file '{s}'", .{file_path});

            cwd.unlinkFile(file_path) catch |err| return command.printErrorAlloc(
                allocator,
                io,
                "failed to unlink '{s}': {s}",
                .{ file_path, @errorName(err) },
            );
        }
    }

    test "unlink no args" {
        try command.testError(
            &.{},
            .{},
            "missing file operand",
        );
    }

    test "unlink no file" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        try command.testError(
            &.{"non-existent"},
            .{
                .system_description = .{ .file_system = fs_description },
            },
            "failed to unlink 'non-existent': FileNotFound",
        );
    }

    test "unlink directory" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        _ = try fs_description.root.addDirectory("dir");

        try command.testError(
            &.{"dir"},
            .{
                .system_description = .{ .file_system = fs_description },
            },
            "failed to unlink 'dir': IsDirectory",
        );
    }

    test "unlink single file" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        _ = try fs_description.root.addFile("file1", "contents");
        _ = try fs_description.root.addFile("file2", "contents");

        var system: System = undefined;
        defer system._backend.destroy();

        try command.testExecute(
            &.{"file1"},
            .{
                .system_description = .{ .file_system = fs_description },
                .test_backend_behaviour = .{ .provide = &system },
            },
        );

        const test_backend: *System.TestBackend = system._backend;
        const file_system = test_backend.file_system.?;

        try std.testing.expect(file_system.root.subdata.dir.entries.get("file1") == null);
        try std.testing.expect(file_system.root.subdata.dir.entries.get("file2") != null);
        try shared.customExpectEqual(file_system.entries.count(), 2); // root and file2
    }

    test "unlink multiple files" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        _ = try fs_description.root.addFile("file1", "contents");
        _ = try fs_description.root.addFile("file2", "contents");

        var system: System = undefined;
        defer system._backend.destroy();

        try command.testExecute(
            &.{ "file1", "file2" },
            .{
                .system_description = .{ .file_system = fs_description },
                .test_backend_behaviour = .{ .provide = &system },
            },
        );

        const test_backend: *System.TestBackend = system._backend;
        const file_system = test_backend.file_system.?;

        try std.testing.expect(file_system.root.subdata.dir.entries.get("file1") == null);
        try std.testing.expect(file_system.root.subdata.dir.entries.get("file2") == null);
        try shared.customExpectEqual(file_system.entries.count(), 1); // root
    }

    test "complex paths" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        {
            const dir1 = try fs_description.root.addDirectory("dir1");
            _ = try dir1.addFile("file1", "contents");
            _ = try dir1.addFile("file2", "contents");

            const dir2 = try dir1.addDirectory("dir2");
            _ = try dir2.addFile("file3", "contents");
            _ = try dir2.addFile("file4", "contents");
        }

        var system: System = undefined;
        defer system._backend.destroy();

        try command.testExecute(
            &.{
                "dir1/file1", // relative to cwd
                "dir1/dir2/../file2", // .. traversal
                "dir1/dir2/file3",
                "/dir1/dir2/file4", // absolute path
            },
            .{
                .system_description = .{ .file_system = fs_description },
                .test_backend_behaviour = .{ .provide = &system },
            },
        );

        const test_backend: *System.TestBackend = system._backend;
        const file_system = test_backend.file_system.?;

        const dir1 = file_system.root.subdata.dir.entries.get("dir1").?.subdata.dir;
        try std.testing.expect(dir1.entries.get("file1") == null);
        try std.testing.expect(dir1.entries.get("file2") == null);

        const dir2 = dir1.entries.get("dir2").?.subdata.dir;
        try std.testing.expect(dir2.entries.get("file3") == null);
        try std.testing.expect(dir2.entries.get("file4") == null);

        try shared.customExpectEqual(file_system.entries.count(), 3); // root, dir1 and dir2
    }

    test "unlink help" {
        try command.testHelp(true);
    }

    test "unlink version" {
        try command.testVersion();
    }

    test "unlink fuzz" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        {
            const dir1 = try fs_description.root.addDirectory("dir1");
            _ = try dir1.addFile("file1", "contents");
            _ = try dir1.addFile("file2", "contents");

            const dir2 = try dir1.addDirectory("dir2");
            _ = try dir2.addFile("file3", "contents");
            _ = try dir2.addFile("file4", "contents");
        }

        try command.testFuzz(.{
            .expect_stdout_output_on_success = false,
            .system_description = .{ .file_system = fs_description },
            .corpus = &.{
                "dir1/file1",
                "dir1/dir2/../file2",
                "dir1/dir2/file3",
                "/dir1/dir2/file4",
            },
        });
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.unlink);

const std = @import("std");
const tracy = @import("tracy");
