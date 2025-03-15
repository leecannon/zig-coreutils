// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "template";

pub const short_help =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\A template command
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `template`
// a blank line is required at the beginning to ensure correct formatting
pub const extended_help = "";

pub fn execute(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) shared.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
    defer z.end();

    _ = cwd;

    const options = try parseArguments(allocator, io, args, exe_path);
    log.debug("options={}", .{options});
}

const TemplateOptions = struct {
    pub fn format(
        options: TemplateOptions,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        try writer.writeAll("TemplateOptions{ }");
    }
};

fn parseArguments(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    exe_path: []const u8,
) !TemplateOptions {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(true);

    const options: TemplateOptions = .{};

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
                @branchHint(.cold);
                state = .{ .invalid_argument = .{ .slice = longhand } };
                break;
            },
            .longhand_with_value => |longhand_with_value| {
                @branchHint(.cold);
                state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                break;
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    @branchHint(.cold);
                    state = .{ .invalid_argument = .{ .character = char } };
                    break;
                }
            },
            .positional => {
                @branchHint(.cold);
                state = .{ .invalid_argument = .{ .slice = arg.raw } };
                break;
            },
        }
    }

    return switch (state) {
        .normal => options,
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

test "template no args" {
    try shared.testExecute(@This(), &.{}, .{});
}

test "template help" {
    try shared.testHelp(@This(), true);
}

test "template version" {
    try shared.testVersion(@This());
}

const log = std.log.scoped(.template);
const shared = @import("../shared.zig");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
