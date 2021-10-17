const std = @import("std");
const subcommands = @import("../subcommands.zig");
const utils = @import("../utils.zig");

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

// io
// .{
//     .stderr: std.io.Writer,
//     .stdin: std.io.Reader,
//     .stdout: std.io.Writer,
// },

pub fn execute(
    allocator: *std.mem.Allocator,
    io: anytype,
    exe_name: []const u8,
    options: OptionsDefinition,
    positionals: [][:0]const u8,
) subcommands.Error!u8 {
    _ = allocator;
    _ = positionals;

    if (options.help) return utils.printHelp(@This(), io, exe_name);
    if (options.version) return utils.printVersion(@This(), io);

    return 0;
}

test "no args" {
    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            @This(),
            &.{},
            .{},
        ),
    );
}

comptime {
    std.testing.refAllDecls(@This());
}
