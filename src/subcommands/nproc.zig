// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>
// SPDX-FileCopyrightText: 2024 Leon Henrik Plickat

pub const name = "nproc";

pub const short_help =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Print the number of processing units available.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `nproc`
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

    _ = try args.nextWithHelpOrVersion(true);

    const path = "/sys/devices/system/cpu/online";
    var buffer: [8]u8 = undefined;
    const file_contents = try shared.readFileIntoBuffer(
        @This(),
        allocator,
        io,
        cwd,
        path,
        &buffer,
    );

    const last_cpu_index = getLastCpuIndex(
        std.mem.trim(u8, file_contents, &std.ascii.whitespace),
    ) catch
        return shared.printError(
            @This(),
            io,
            "format of '" ++ path ++ "' is invalid: '{s}'",
        );

    io.stdout.print("{}\n", .{1 + last_cpu_index}) catch |err|
        return shared.unableToWriteTo("stdout", io, err);
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
    try subcommands.testHelp(@This(), true);
}

test "nproc version" {
    try subcommands.testVersion(@This());
}

const log = std.log.scoped(.nproc);
const shared = @import("../shared.zig");
const std = @import("std");
const subcommands = @import("../subcommands.zig");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
