const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.template);

pub const name = "template";

pub const usage =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\A template subcommand
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
    \\
;

pub const Options = struct {};

pub fn parseOptions(
    io: anytype,
    options: *Options,
    args: *shared.ArgIterator,
    exe_name: []const u8,
) ?u8 {
    _ = options;

    const z = shared.trace.begin(@src());
    defer z.end();

    while (args.next()) |arg| {
        switch (arg) {
            .longhand => |longhand| {
                if (std.mem.eql(u8, longhand, "help")) {
                    return shared.printHelp(@This(), io, exe_name);
                }
                if (std.mem.eql(u8, longhand, "version")) {
                    return shared.printVersion(@This(), io);
                }
            },
            .shorthand => |shorthand| {
                if (shorthand == 'h') {
                    return shared.printHelp(@This(), io, exe_name);
                }
            },
            .positional => {},
        }
    }

    return null;
}

// io
// .{
//     .stderr: std.io.Writer,
//     .stdin: std.io.Reader,
//     .stdout: std.io.Writer,
// },

pub fn execute(
    allocator: *std.mem.Allocator,
    io: anytype,
    options: *Options,
) subcommands.Error!u8 {
    _ = allocator;
    _ = io;

    const z = shared.trace.begin(@src());
    defer z.end();

    log.debug("called with options: {}", .{options});

    return 0;
}

test "template no args" {
    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            @This(),
            &.{},
            .{},
        ),
    );
}

test "template help" {
    try shared.testHelp(@This());
}

test "template version" {
    try shared.testVersion(@This());
}

comptime {
    std.testing.refAllDecls(@This());
}
