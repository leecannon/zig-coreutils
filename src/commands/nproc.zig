// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>
// SPDX-FileCopyrightText: 2024 Leon Henrik Plickat

/// Is this command enabled for the current target?
pub const enabled: bool = shared.target_os == .linux; // TODO: support other OSes

pub const command: Command = .{
    .name = "nproc",

    .short_help =
    \\Usage: {NAME} [ignored command line arguments]
    \\   or: {NAME} OPTION
    \\
    \\Print the number of processing units available.
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

        const path = "/sys/devices/system/cpu/online";

        var buffer: [8]u8 = undefined;

        const file_contents = blk: {
            const file = system.cwd().openFile(path, .{}) catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to open '{s}': {s}",
                    .{ path, @errorName(err) },
                );
            defer if (shared.free_on_close) file.close();

            const read = file.readAll(&buffer) catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "unable to read file '{s}': {s}",
                    .{ path, @errorName(err) },
                );

            break :blk buffer[0..read];
        };

        const last_cpu_index = getLastCpuIndex(
            std.mem.trim(u8, file_contents, &std.ascii.whitespace),
        ) catch
            return command.printError(
                io,
                "format of '" ++ path ++ "' is invalid: '{s}'",
            );

        try io.stdoutPrint("{}\n", .{1 + last_cpu_index});
    }

    fn getLastCpuIndex(str: []const u8) error{InvalidFormat}!usize {
        // Contains string like "0-3" listing the index range of the processors.
        var it = std.mem.splitScalar(u8, str, '-');
        // Also catches str.len == 0.
        if (it.next() == null) return error.InvalidFormat;
        const last_index_str = it.next() orelse return error.InvalidFormat;
        const last_index = std.fmt.parseInt(usize, last_index_str, 10) catch return error.InvalidFormat;
        if (it.next() != null) return error.InvalidFormat;
        return last_index;
    }

    test getLastCpuIndex {
        const valid_input = "0-3";
        try std.testing.expect(try getLastCpuIndex(valid_input) == 3);
        const invalid_input_a = "0-";
        try std.testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_a));
        const invalid_input_b = "0";
        try std.testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_b));
        const invalid_input_c = "0-4-5";
        try std.testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_c));
        const invalid_input_d = "invalid";
        try std.testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_d));
        const invalid_input_e = "";
        try std.testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_e));
    }

    test "nproc help" {
        try command.testHelp(true);
    }

    test "nproc version" {
        try command.testVersion();
    }

    test "nproc" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        const sys_dir = try fs_description.root.addDirectory("sys");
        const devices_dir = try sys_dir.addDirectory("devices");
        const system_dir = try devices_dir.addDirectory("system");
        const cpu_dir = try system_dir.addDirectory("cpu");
        _ = try cpu_dir.addFile("online", "0-15");

        var stdout: std.ArrayList(u8) = .init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(&.{}, .{
            .stdout = stdout.writer().any(),
            .system_description = .{
                .file_system = fs_description,
            },
        });

        try std.testing.expectEqualStrings("16\n", stdout.items);
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const std = @import("std");
const tracy = @import("tracy");
