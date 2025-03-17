// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>
// SPDX-FileCopyrightText: 2024 Leon Henrik Plickat

// TODO: How do we test this without introducing the amount of complexity that https://github.com/leecannon/zsw does?
// https://github.com/leecannon/zig-coreutils/issues/1

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

    const path = "/sys/devices/system/cpu/online";
    var buffer: [8]u8 = undefined;
    const file_contents = try shared.readFileIntoBuffer(
        command,
        allocator,
        io,
        cwd,
        path,
        &buffer,
    );

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

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.nproc);

const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
