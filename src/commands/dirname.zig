// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "dirname";

pub const short_help =
    \\Usage: {0s} [OPTION] NAME...
    \\
    \\Print each NAME with its last non-slash components and trailing slashes removed.
    \\If NAME contains no slashes outputs '.' (the current directory).
    \\
    \\  -z, --zero  end each output line with NUL, not newline
    \\  -h          display the short help and exit
    \\  --help      display the full help and exit
    \\  --version   output version information and exit
    \\
;

pub const extended_help = // a blank line is required at the beginning to ensure correct formatting
    \\
    \\Examples:
    \\  dirname /usr/bin/          -> "/usr"
    \\  dirname dir1/str dir2/str  -> "dir1" followed by "dir2"
    \\  dirname stdio.h            -> "."
    \\
;

pub fn execute(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) shared.CommandError!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
    defer z.end();

    _ = cwd;

    const options = try parseArguments(allocator, io, args, exe_path);
    log.debug("options={}", .{options});

    return performDirname(io, args, options);
}

const DirnameOptions = struct {
    line_end: LineEnd = .newline,
    first_arg: []const u8 = undefined,

    const LineEnd = enum(u8) {
        newline = '\n',
        zero = 0,
    };

    pub fn format(
        options: DirnameOptions,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("DirnameOptions{ .line_end = .");
        try writer.writeAll(@tagName(options.line_end));
        try writer.writeAll(", .first_arg = \"");
        try writer.writeAll(options.first_arg);
        try writer.writeAll("\" }");
    }
};

fn performDirname(
    io: shared.IO,
    args: *shared.ArgIterator,
    options: DirnameOptions,
) !void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "perform dirname" });
    defer z.end();

    log.debug("performDirname called", .{});

    var opt_arg: ?[]const u8 = options.first_arg;

    while (opt_arg) |arg| : (opt_arg = args.nextRaw()) {
        const argument_zone: tracy.Zone = .begin(.{ .src = @src(), .name = "process arg" });
        defer argument_zone.end();
        argument_zone.text(arg);

        const dirname = if (std.fs.path.dirname(arg)) |dir|
            dir
        else
            ".";
        log.debug("got dirname: '{s}'", .{dirname});

        io.stdout.writeAll(dirname) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
        io.stdout.writeByte(@intFromEnum(options.line_end)) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
    }
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: shared.IO,
    args: *shared.ArgIterator,
    exe_path: []const u8,
) !DirnameOptions {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(true);

    var dir_options: DirnameOptions = .{};

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
                if (std.mem.eql(u8, longhand, "zero")) {
                    dir_options.line_end = .zero;
                    log.debug("got zero longhand", .{});
                } else {
                    @branchHint(.cold);
                    state = .{ .invalid_argument = .{ .slice = longhand } };
                    break;
                }
            },
            .longhand_with_value => |longhand_with_value| {
                @branchHint(.cold);
                state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                break;
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (char == 'z') {
                        dir_options.line_end = .zero;
                        log.debug("got zero shorthand", .{});
                    } else {
                        @branchHint(.cold);
                        state = .{ .invalid_argument = .{ .character = char } };
                        break;
                    }
                }
            },
            .positional => {
                dir_options.first_arg = arg.raw;
                return dir_options;
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

test "dirname no args" {
    try shared.testError(@This(), &.{}, .{}, "missing operand");
}

test "dirname single" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try shared.testExecute(
        @This(),
        &.{
            "hello/world",
        },
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings("hello\n", stdout.items);
}

test "dirname multiple" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try shared.testExecute(
        @This(),
        &.{
            "hello/world",
            "this/is/a/test",
            "a/b/c/d",
        },
        .{ .stdout = stdout.writer() },
    );

    try std.testing.expectEqualStrings(
        \\hello
        \\this/is/a
        \\a/b/c
        \\
    , stdout.items);
}

test "dirname help" {
    try shared.testHelp(@This(), true);
}

test "dirname version" {
    try shared.testVersion(@This());
}

const log = std.log.scoped(.dirname);
const shared = @import("../shared.zig");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
