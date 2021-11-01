const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.@"false");

pub const name = "false";

pub const usage =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\Exit with a status code indicating failure.
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
    \\
;

// io
// .{
//     .stderr: std.io.Writer,
//     .stdin: std.io.Reader,
//     .stdout: std.io.Writer,
// },

// args
// struct {
//     fn next(self: *Self) !?shared.Arg,
//
//     // intended to only be called for the first argument
//     fn nextWithHelpOrVersion(self: *Self) !?shared.Arg,
// }

pub fn execute(
    allocator: *std.mem.Allocator,
    io: anytype,
    args: anytype,
) subcommands.Error!u8 {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = io;

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion();

    while (opt_arg) |arg| : ({
        arg.deinit(allocator);
        opt_arg = try args.next();
    }) {
        switch (arg) {
            .longhand => {},
            .shorthand => {},
            .longhand_with_value => {},
            .positional => {},
        }
    }

    log.debug("false called", .{});

    return 1;
}

test "false no args" {
    try std.testing.expectEqual(
        @as(u8, 1),
        try subcommands.testExecute(
            @This(),
            &.{},
            .{},
        ),
    );
}

test "false help" {
    try shared.testHelp(@This());
}

test "false version" {
    try shared.testVersion(@This());
}

comptime {
    std.testing.refAllDecls(@This());
}
