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
    io: anytype,
    args: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z: shared.tracy.Zone = .begin(.{ .src = @src(), .name = name });
    defer z.end();

    _ = cwd;

    const options = try parseArguments(allocator, io, args, exe_path);

    return performDirname(io, args, options);
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    exe_path: []const u8,
) !DirnameOptions {
    const z: shared.tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
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
                if (state != .normal) break;

                if (std.mem.eql(u8, longhand, "zero")) {
                    dir_options.zero = true;
                    log.debug("got zero longhand", .{});
                } else {
                    state = .{ .invalid_argument = .{ .slice = longhand } };
                    break;
                }
            },
            .longhand_with_value => |longhand_with_value| {
                state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                break;
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (state != .normal) break;

                    if (char == 'z') {
                        dir_options.zero = true;
                        log.debug("got zero shorthand", .{});
                    } else {
                        state = .{ .invalid_argument = .{ .character = char } };
                        break;
                    }
                }
            },
            .positional => {
                if (state != .normal) break;

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

const DirnameOptions = struct {
    zero: bool = false,

    first_arg: []const u8 = undefined,
};

fn performDirname(
    io: anytype,
    args: anytype,
    options: DirnameOptions,
) !void {
    const z: shared.tracy.Zone = .begin(.{ .src = @src(), .name = "perform dirname" });
    defer z.end();

    log.debug("performDirname called, options={}", .{options});

    const end_byte: u8 = if (options.zero) 0 else '\n';

    var opt_arg: ?[]const u8 = options.first_arg;

    while (opt_arg) |arg| : (opt_arg = args.nextRaw()) {
        const argument_zone: shared.tracy.Zone = .begin(.{ .src = @src(), .name = "process arg" });
        defer argument_zone.end();
        argument_zone.text(arg);

        const dirname = getDirname(arg);
        log.debug("got dirname: '{s}'", .{dirname});

        io.stdout.writeAll(dirname) catch |err| return shared.unableToWriteTo("stdout", io, err);
        io.stdout.writeByte(end_byte) catch |err| return shared.unableToWriteTo("stdout", io, err);
    }
}

fn getDirname(buf: []const u8) []const u8 {
    if (std.fs.path.dirname(buf)) |dir| return dir;
    return ".";
}

test "dirname no args" {
    try subcommands.testError(@This(), &.{}, .{}, "missing operand");
}

test "dirname single" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try subcommands.testExecute(
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

    try subcommands.testExecute(
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
    try subcommands.testHelp(@This(), true);
}

test "dirname version" {
    try subcommands.testVersion(@This());
}

const help_zls = struct {
    // Due to https://github.com/zigtools/zls/pull/1067 this is enough to help ZLS understand the `io` and `args` arguments

    fn dummyExecute() void {
        execute(
            undefined,
            @as(DummyIO, undefined),
            @as(DummyArgs, undefined),
            undefined,
            undefined,
        );
        @panic("THIS SHOULD NEVER BE CALLED");
    }

    const DummyIO = struct {
        stderr: std.io.Writer,
        stdin: std.io.Reader,
        stdout: std.io.Writer,
    };

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

const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const log = std.log.scoped(.dirname);

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
