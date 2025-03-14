// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "clear";

pub const short_help =
    \\Usage: {0s} [OPTION]
    \\
    \\Clear the screen.
    \\
    \\  -x         don't clear the scrollback
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `clear`
pub const extended_help = "";

pub fn execute(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
    defer z.end();

    _ = cwd;

    const options = try parseArguments(allocator, io, args, exe_path);

    const output = if (options.clear_scrollback) "\x1b[H\x1b[2J\x1b[3J" else "\x1b[H\x1b[2J";

    io.stdout.writeAll(output) catch |err| return shared.unableToWriteTo("stdout", io, err);
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: anytype,
    exe_path: []const u8,
) !ClearOptions {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(true);

    var clear_options: ClearOptions = .{};

    const State = union(enum) {
        normal,
        invalid_argument: Argument,

        const Argument = union(enum) {
            slice: []const u8,
            character: u8,
        };
    };

    var state: State = .normal;

    while (opt_arg) |*arg| : (opt_arg = args.next()) {
        switch (arg.arg_type) {
            .longhand => |longhand| {
                if (state != .normal) break;
                state = .{ .invalid_argument = .{ .slice = longhand } };
                break;
            },
            .longhand_with_value => |longhand_with_value| {
                if (state != .normal) break;
                state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                break;
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (state != .normal) break;

                    if (char == 'x') {
                        clear_options.clear_scrollback = false;
                        log.debug("got dont clear scrollback option", .{});
                    } else {
                        state = .{ .invalid_argument = .{ .character = char } };
                        break;
                    }
                }
            },
            .positional => {
                if (state != .normal) break;
                state = .{ .invalid_argument = .{ .slice = arg.raw } };
                break;
            },
        }
    }

    return switch (state) {
        .normal => clear_options,
        .invalid_argument => |invalid_arg| switch (invalid_arg) {
            .slice => |slice| shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "unrecognized option '--{s}'",
                .{slice},
            ),
            .character => |character| shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "unrecognized option -- '{c}'",
                .{character},
            ),
        },
    };
}

const ClearOptions = struct {
    clear_scrollback: bool = true,
};

test "clear no args" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try subcommands.testExecute(
        @This(),
        &.{},
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings("\x1b[H\x1b[2J\x1b[3J", stdout.items);
}

test "clear - don't clear scrollback" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try subcommands.testExecute(
        @This(),
        &.{"-x"},
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings("\x1b[H\x1b[2J", stdout.items);
}

test "clear help" {
    try subcommands.testHelp(@This(), true);
}

test "clear version" {
    try subcommands.testVersion(@This());
}

const help_zls = struct {
    // Due to https://github.com/zigtools/zls/pull/1067 this is enough to help ZLS understand the `args` argument

    fn dummyExecute() void {
        execute(
            undefined,
            undefined,
            @as(DummyArgs, undefined),
            undefined,
            undefined,
        );
        @panic("THIS SHOULD NEVER BE CALLED");
    }

    const DummyArgs = struct {
        const Self = @This();

        fn next(self: *Self) ?shared.Arg {
            _ = self;
            @panic("THIS SHOULD NEVER BE CALLED");
        }

        /// intended to only be called for the first argument
        fn nextWithHelpOrVersion(self: *Self, comptime include_shorthand: bool) !?shared.Arg {
            _ = include_shorthand;
            _ = self;
            @panic("THIS SHOULD NEVER BE CALLED");
        }

        fn nextRaw(self: *Self) ?[]const u8 {
            _ = self;
            @panic("THIS SHOULD NEVER BE CALLED");
        }
    };
};

const log = std.log.scoped(.clear);
const shared = @import("../shared.zig");
const std = @import("std");
const subcommands = @import("../subcommands.zig");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
