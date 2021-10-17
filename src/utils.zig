const std = @import("std");

pub fn printHelp(comptime Self: type, io: anytype, exe_path: []const u8) u8 {
    io.stdout.print(Self.usage, .{exe_path}) catch {};
    return 0;
}

pub fn printVersion(comptime Self: type, io: anytype) u8 {
    io.stdout.print(
        \\{s} (zig-coreutils) 0.0.1
        \\MIT License Copyright (c) 2021 Lee Cannon
        \\
    , .{Self.name}) catch {};
    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
