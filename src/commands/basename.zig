// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const command: Command = .{
    .name = "basename",

    .short_help =
    \\Usage: {NAME} NAME [SUFFIX]
    \\   or: {NAME} OPTION... NAME...
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
    ,

    .extended_help =
    \\Examples:
    \\  basename /usr/bin/sort          -> "sort"
    \\  basename include/stdio.h .h     -> "stdio"
    \\  basename -s .h include/stdio.h  -> "stdio"
    \\  basename -a any/str1 any/str2   -> "str1" followed by "str2"
    \\
    ,

    .execute = execute,
};

fn execute(
    allocator: std.mem.Allocator,
    io: IO,
    args: *Arg.Iterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) Command.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = command.name });
    defer z.end();

    _ = cwd;

    const options = try parseArguments(allocator, io, args, exe_path);
    log.debug("options={}", .{options});

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
        /// Value is optional suffix
        multiple: ?[]const u8,
    };

    pub fn format(
        options: BasenameOptions,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("BasenameOptions{ .line_end = .");
        try writer.writeAll(@tagName(options.line_end));

        try writer.writeAll(", .mode = .");
        switch (options.mode) {
            .single => try writer.writeAll("single"),
            .multiple => |opt_suffix| {
                if (opt_suffix) |suffix| {
                    try writer.writeAll("multiple, .suffix = \"");
                    try writer.writeAll(suffix);
                    try writer.writeAll("\"");
                } else {
                    try writer.writeAll("multiple");
                }
            },
        }

        try writer.writeAll(", .first_arg = \"");
        try writer.writeAll(options.first_arg);
        try writer.writeAll("\" }");
    }
};

fn singleArgument(
    allocator: std.mem.Allocator,
    io: IO,
    args: *Arg.Iterator,
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
            return command.printInvalidUsageAlloc(
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

    log.debug("singleArgument called", .{});

    const basename = getBasename(options.first_arg, opt_suffix);
    log.debug("got basename: '{s}'", .{basename});

    try io.stdoutWriteAll(basename);
    try io.stdoutWriteByte(@intFromEnum(options.line_end));
}

fn multipleArguments(
    io: IO,
    args: *Arg.Iterator,
    options: BasenameOptions,
) !void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "multiple arguments" });
    defer z.end();

    log.debug("multipleArguments called", .{});

    var opt_arg: ?[]const u8 = options.first_arg;

    while (opt_arg) |arg| : (opt_arg = args.nextRaw()) {
        const argument_zone: tracy.Zone = .begin(.{ .src = @src(), .name = "process arg" });
        defer argument_zone.end();
        argument_zone.text(arg);

        const basename = getBasename(arg, options.mode.multiple);
        log.debug("got basename: '{s}'", .{basename});

        try io.stdoutWriteAll(basename);
        try io.stdoutWriteByte(@intFromEnum(options.line_end));
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
    io: IO,
    args: *Arg.Iterator,
    exe_path: []const u8,
) !BasenameOptions {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
    defer z.end();

    var opt_arg: ?Arg = try args.nextWithHelpOrVersion(true);

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
        .normal => command.printInvalidUsage(
            io,
            exe_path,
            "missing operand",
        ),
        .suffix => command.printInvalidUsage(
            io,
            exe_path,
            "expected SUFFIX for suffix argument",
        ),
        .invalid_argument => |invalid_arg| switch (invalid_arg) {
            .slice => |slice| command.printInvalidUsageAlloc(
                allocator,
                io,
                exe_path,
                "unrecognized option '{s}'",
                .{slice},
            ),
            .character => |character| command.printInvalidUsageAlloc(
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
    try command.testError(
        &.{},
        .{},
        "missing operand",
    );
}

test "basename single" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try command.testExecute(
        &.{"hello/world"},
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings("world\n", stdout.items);
}

test "basename multiple" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try command.testExecute(
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
    try command.testHelp(true);
}

test "basename version" {
    try command.testVersion();
}

test "basename fuzz" {
    try command.testFuzz(.{});
}

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.basename);

const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
