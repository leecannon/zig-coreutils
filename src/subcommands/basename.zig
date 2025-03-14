// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "basename";

pub const short_help =
    \\Usage: {0s} NAME [SUFFIX]
    \\   or: {0s} OPTION... NAME...
    \\
    \\Print NAME with any leading directory components removed.
    \\If specified, also remove a trailing SUFFIX.
    \\
    \\Mandatory arguments to long options are mandatory for short options too.
    \\  -a, --multiple       support multiple arguments and treat each as a NAME
    \\  -s, --suffix=SUFFIX  remove a trailing SUFFIX; implies -a
    \\  -z, --zero           end each output line with NUL, not newline
    \\  -h                   display the short help and exit
    \\  --help               display the full help and exit
    \\  --version            output version information and exit
    \\
;

pub const extended_help = // a blank line is required at the beginning to ensure correct formatting
    \\
    \\Examples:
    \\  basename /usr/bin/sort          -> "sort"
    \\  basename include/stdio.h .h     -> "stdio"
    \\  basename -s .h include/stdio.h  -> "stdio"
    \\  basename -a any/str1 any/str2   -> "str1" followed by "str2"
    \\
;

pub fn execute(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
    defer z.end();

    _ = cwd;

    const options = try parseArguments(allocator, io, args, exe_path);

    return switch (options.mode) {
        .single => singleArgument(allocator, io, args, exe_path, options),
        .multiple => multipleArguments(io, args, options),
    };
}

const BasenameOptions = struct {
    line_end: LineEnd = .newline,
    mode: Mode = .single,
    first_arg: []const u8 = undefined,

    const LineEnd = enum(u8) {
        newline = '\n',
        zero = 0,
    };

    const Mode = union(enum) {
        single,
        multiple: ?[]const u8,
    };
};

fn singleArgument(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    exe_path: []const u8,
    options: BasenameOptions,
) !void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "single argument" });
    defer z.end();
    z.text(options.first_arg);

    const opt_suffix: ?[]const u8 = blk: {
        const suffix_zone: tracy.Zone = .begin(.{ .src = @src(), .name = "get suffix" });
        defer suffix_zone.end();

        const arg = args.nextRaw() orelse break :blk null;

        if (args.nextRaw()) |additional_arg| {
            return shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "extra operand '{s}'",
                .{additional_arg},
            );
        }

        suffix_zone.text(arg);

        break :blk arg;
    };

    log.debug("singleArgument called, options={}", .{options});

    const basename = getBasename(options.first_arg, opt_suffix);
    log.debug("got basename: '{s}'", .{basename});

    io.stdout.writeAll(basename) catch |err|
        return shared.unableToWriteTo("stdout", io, err);
    io.stdout.writeByte(@intFromEnum(options.line_end)) catch |err|
        return shared.unableToWriteTo("stdout", io, err);
}

fn multipleArguments(
    io: shared.IO,
    args: *shared.ArgIterator,
    options: BasenameOptions,
) !void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "multiple arguments" });
    defer z.end();

    log.debug("multipleArguments called, options={}", .{options});

    var opt_arg: ?[]const u8 = options.first_arg;

    while (opt_arg) |arg| : (opt_arg = args.nextRaw()) {
        const argument_zone: tracy.Zone = .begin(.{ .src = @src(), .name = "process arg" });
        defer argument_zone.end();
        argument_zone.text(arg);

        const basename = getBasename(arg, options.mode.multiple);
        log.debug("got basename: '{s}'", .{basename});

        io.stdout.writeAll(basename) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
        io.stdout.writeByte(@intFromEnum(options.line_end)) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
    }
}

fn getBasename(buf: []const u8, opt_suffix: ?[]const u8) []const u8 {
    const basename = std.fs.path.basename(buf);

    const suffix = opt_suffix orelse return basename;

    const end_index = std.mem.lastIndexOf(u8, basename, suffix) orelse return basename;

    return basename[0..end_index];
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    exe_path: []const u8,
) !BasenameOptions {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(true);

    var basename_options: BasenameOptions = .{};

    const State = union(enum) {
        normal,
        suffix,
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
                if (state != .normal) {
                    @branchHint(.cold);
                    break;
                }

                if (std.mem.eql(u8, longhand, "zero")) {
                    basename_options.line_end = .zero;
                    log.debug("got zero longhand", .{});
                } else if (std.mem.eql(u8, longhand, "multiple")) {
                    if (basename_options.mode != .multiple) {
                        basename_options.mode = .{ .multiple = null };
                    }
                    log.debug("got multiple longhand", .{});
                } else if (std.mem.eql(u8, longhand, "suffix")) {
                    state = .suffix;
                    log.debug("got suffix longhand", .{});
                } else {
                    @branchHint(.cold);
                    state = .{
                        .invalid_argument = .{ .slice = longhand },
                    };
                    break;
                }
            },
            .longhand_with_value => |longhand_with_value| {
                if (state != .normal) {
                    @branchHint(.cold);
                    break;
                }

                if (std.mem.eql(u8, longhand_with_value.longhand, "suffix")) {
                    basename_options.mode = .{ .multiple = longhand_with_value.value };
                    log.debug("got suffix longhand with value = {s}", .{longhand_with_value.value});
                } else {
                    @branchHint(.cold);
                    state = .{
                        .invalid_argument = .{ .slice = longhand_with_value.longhand },
                    };
                    break;
                }
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (state != .normal) {
                        @branchHint(.cold);
                        break;
                    }

                    if (char == 'z') {
                        basename_options.line_end = .zero;
                        log.debug("got zero shorthand", .{});
                    } else if (char == 'a') {
                        if (basename_options.mode != .multiple) {
                            basename_options.mode = .{ .multiple = null };
                        }
                        log.debug("got multiple shorthand", .{});
                    } else if (char == 's') {
                        state = .suffix;
                        log.debug("got suffix shorthand", .{});
                    } else {
                        @branchHint(.cold);
                        state = .{
                            .invalid_argument = .{ .character = char },
                        };
                        break;
                    }
                }
            },
            .positional => {
                switch (state) {
                    .normal => {},
                    .suffix => {
                        basename_options.mode = .{ .multiple = arg.raw };
                        log.debug("got suffix value: '{s}'", .{arg.raw});
                        state = .normal;
                        continue;
                    },
                    else => {
                        @branchHint(.cold);
                        break;
                    },
                }

                basename_options.first_arg = arg.raw;
                return basename_options;
            },
        }
    }

    return switch (state) {
        .normal => shared.printInvalidUsage(
            @This(),
            io,
            exe_path,
            "missing operand",
        ),
        .suffix => shared.printInvalidUsage(
            @This(),
            io,
            exe_path,
            "expected SUFFIX for suffix argument",
        ),
        .invalid_argument => |invalid_arg| switch (invalid_arg) {
            .slice => |slice| shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "unrecognized option '{s}'",
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

test "basename no args" {
    try subcommands.testError(
        @This(),
        &.{},
        .{},
        "missing operand",
    );
}

test "basename single" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try subcommands.testExecute(
        @This(),
        &.{"hello/world"},
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings("world\n", stdout.items);
}

test "basename multiple" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try subcommands.testExecute(
        @This(),
        &.{
            "-a",
            "hello/world",
            "this/is/a/test",
            "a/b/c/d",
        },
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings(
        \\world
        \\test
        \\d
        \\
    , stdout.items);
}

test "basename help" {
    try subcommands.testHelp(@This(), true);
}

test "basename version" {
    try subcommands.testVersion(@This());
}

const log = std.log.scoped(.basename);
const shared = @import("../shared.zig");
const std = @import("std");
const subcommands = @import("../subcommands.zig");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
