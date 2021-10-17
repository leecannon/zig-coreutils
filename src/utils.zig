const std = @import("std");
const subcommands = @import("subcommands.zig");

const log = std.log.scoped(.utils);

pub fn printHelp(comptime subcommand: type, io: anytype, exe_path: []const u8) u8 {
    log.debug("printing help for " ++ subcommand.name, .{});
    io.stdout.print(subcommand.usage, .{exe_path}) catch {};
    return 0;
}

pub fn printVersion(comptime subcommand: type, io: anytype) u8 {
    log.debug("printing version for " ++ subcommand.name, .{});
    io.stdout.print(version_string, .{subcommand.name}) catch {};
    return 0;
}

const version_string =
    \\{s} (zig-coreutils) 0.0.1
    \\MIT License Copyright (c) 2021 Lee Cannon
    \\
;

pub fn testHelp(comptime subcommand: type) !void {
    const expected = try std.fmt.allocPrint(std.testing.allocator, subcommand.usage, .{subcommand.name});
    defer std.testing.allocator.free(expected);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            subcommand,
            &.{"--help"},
            .{ .stdout = out.writer() },
        ),
    );

    try std.testing.expectEqualStrings(expected, out.items);

    out.deinit();
    out = std.ArrayList(u8).init(std.testing.allocator);

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            subcommand,
            &.{"-h"},
            .{ .stdout = out.writer() },
        ),
    );

    try std.testing.expectEqualStrings(expected, out.items);
}

pub fn testVersion(comptime subcommand: type) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            subcommand,
            &.{"--version"},
            .{ .stdout = out.writer() },
        ),
    );

    const expected = try std.fmt.allocPrint(std.testing.allocator, version_string, .{subcommand.name});
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, out.items);
}

comptime {
    std.testing.refAllDecls(@This());
}
