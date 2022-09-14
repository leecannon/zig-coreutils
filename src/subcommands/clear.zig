const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const zsw = @import("zsw");

const log = std.log.scoped(.clear);

pub const name = "clear";

pub const usage =
    \\Usage: {0s} [OPTION]
    \\
    \\Clear the screen.
    \\
    \\     -x          don't clear the scrollback
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
//     fn next(self: *Self) ?shared.Arg,
//
//     // intended to only be called for the first argument
//     fn nextWithHelpOrVersion(self: *Self) !?shared.Arg,
//
//     fn nextRaw(self: *Self) ?[]const u8,
// }

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    system: zsw.System,
    exe_path: []const u8,
) subcommands.Error!u8 {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = system;

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion();

    var clear_scrollback = true;

    while (opt_arg) |*arg| : (opt_arg = args.next()) {
        switch (arg.arg_type) {
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (char == 'x') {
                        clear_scrollback = false;
                        log.debug("got dont clear scrollback option", .{});
                    } else {
                        return try shared.printInvalidUsageAlloc(
                            @This(),
                            allocator,
                            io,
                            exe_path,
                            "unrecognized option -- '{c}'",
                            .{char},
                        );
                    }
                }
            },
            else => {
                return try shared.printInvalidUsageAlloc(
                    @This(),
                    allocator,
                    io,
                    exe_path,
                    "unrecognized option '{s}'",
                    .{arg.raw},
                );
            },
        }
    }

    io.stdout.writeAll(if (clear_scrollback) "\x1b[H\x1b[2J\x1b[3J" else "\x1b[H\x1b[2J") catch |err| {
        shared.unableToWriteTo("stdout", io, err);
        return 1;
    };

    return 0;
}

test "clear no args" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    const ret = try subcommands.testExecute(@This(), &.{}, .{
        .stdout = stdout.writer(),
    });

    try std.testing.expect(ret == 0);
    try std.testing.expectEqualStrings("\x1b[H\x1b[2J\x1b[3J", stdout.items);
}

test "clear - don't clear scrollback" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    const ret = try subcommands.testExecute(@This(), &.{"-x"}, .{
        .stdout = stdout.writer(),
    });

    try std.testing.expect(ret == 0);
    try std.testing.expectEqualStrings("\x1b[H\x1b[2J", stdout.items);
}

test "clear help" {
    try subcommands.testHelp(@This());
}

test "clear version" {
    try subcommands.testVersion(@This());
}

comptime {
    std.testing.refAllDecls(@This());
}
