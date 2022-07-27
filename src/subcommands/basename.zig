const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const zsw = @import("zsw");

const log = std.log.scoped(.basename);

pub const name = "basename";

pub const usage =
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
    \\      --help     display this help and exit
    \\      --version  output version information and exit
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
    _ = system;

    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion();

    var zero: bool = false;
    var multiple: bool = false;
    var opt_multiple_suffix: ?[]const u8 = null;

    while (opt_arg) |*arg| : (opt_arg = args.next()) {
        switch (arg.arg_type) {
            .longhand => |longhand| {
                if (std.mem.eql(u8, longhand, "zero")) {
                    zero = true;
                    log.debug("got zero longhand", .{});
                } else if (std.mem.eql(u8, longhand, "multiple")) {
                    multiple = true;
                    log.debug("got multiple longhand", .{});
                } else if (std.mem.eql(u8, longhand, "suffix")) {
                    return shared.printInvalidUsage(
                        @This(),
                        io,
                        exe_path,
                        "option '--suffix' requires an argument",
                    );
                } else {
                    return try shared.printInvalidUsageAlloc(
                        @This(),
                        allocator,
                        io,
                        exe_path,
                        "unrecognized option '--{s}'",
                        .{longhand},
                    );
                }
            },
            .longhand_with_value => |longhand_with_value| {
                if (std.mem.eql(u8, longhand_with_value.longhand, "suffix")) {
                    multiple = true;
                    opt_multiple_suffix = longhand_with_value.value;
                    log.debug("got suffix longhand with value = {s}", .{longhand_with_value.value});
                } else {
                    return try shared.printInvalidUsageAlloc(
                        @This(),
                        allocator,
                        io,
                        exe_path,
                        "unrecognized option '{s}'",
                        .{longhand_with_value.value},
                    );
                }
            },
            .positional => {
                if (multiple) {
                    return try multipleArguments(
                        io,
                        args,
                        arg.raw,
                        zero,
                        opt_multiple_suffix,
                    );
                }
                return try singleArgument(allocator, io, args, exe_path, arg.raw, zero);
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (char == 'z') {
                        zero = true;
                        log.debug("got zero shorthand", .{});
                    } else if (char == 'a') {
                        multiple = true;
                        log.debug("got multiple shorthand", .{});
                    } else if (char == 's') {
                        opt_multiple_suffix = args.nextRaw() orelse {
                            return shared.printInvalidUsage(
                                @This(),
                                io,
                                exe_path,
                                "option requires an argument -- 's'",
                            );
                        };
                        multiple = true;
                        log.debug("got suffix shorthand with value = {s}", .{opt_multiple_suffix orelse unreachable});
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
        }
    }

    return shared.printInvalidUsage(@This(), io, exe_path, "missing operand");
}

fn singleArgument(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    exe_path: []const u8,
    first_arg: []const u8,
    zero: bool,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "single argument");
    defer z.end();
    z.addText(first_arg);

    const opt_suffix: ?[]const u8 = blk: {
        const suffix_zone = shared.tracy.traceNamed(@src(), "get suffix");
        defer suffix_zone.end();

        const arg = args.nextRaw() orelse break :blk null;

        if (args.nextRaw()) |additional_arg| {
            return try shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "extra operand '{s}'",
                .{additional_arg},
            );
        }

        suffix_zone.addText(arg);

        break :blk arg;
    };

    log.info("singleArgument called, first_arg='{s}', zero={}, suffix='{?s}'", .{ first_arg, zero, opt_suffix });

    const basename = getBasename(first_arg, opt_suffix);
    log.debug("got basename: '{s}'", .{basename});

    io.stdout.writeAll(basename) catch |err| {
        shared.unableToWriteTo("stdout", io, err);
        return 1;
    };

    io.stdout.writeByte(if (zero) 0 else '\n') catch |err| {
        shared.unableToWriteTo("stdout", io, err);
        return 1;
    };

    return 0;
}

fn multipleArguments(
    io: anytype,
    args: anytype,
    first_arg: []const u8,
    zero: bool,
    opt_suffix: ?[]const u8,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "multiple arguments");
    defer z.end();

    log.info("multipleArguments called, first_arg='{s}', zero={}, suffix='{?s}'", .{ first_arg, zero, opt_suffix });

    const end_byte: u8 = if (zero) 0 else '\n';

    var opt_arg: ?[]const u8 = first_arg;

    var arg_frame = shared.tracy.namedFrame("arg");
    defer arg_frame.end();

    while (opt_arg) |arg| : ({
        arg_frame.mark();
        opt_arg = args.nextRaw();
    }) {
        const argument_zone = shared.tracy.traceNamed(@src(), "process arg");
        defer argument_zone.end();
        argument_zone.addText(arg);

        const basename = getBasename(arg, opt_suffix);
        log.debug("got basename: '{s}'", .{basename});

        io.stdout.writeAll(basename) catch |err| {
            shared.unableToWriteTo("stdout", io, err);
            return 1;
        };

        io.stdout.writeByte(end_byte) catch |err| {
            shared.unableToWriteTo("stdout", io, err);
            return 1;
        };
    }

    return 0;
}

fn getBasename(buf: []const u8, opt_suffix: ?[]const u8) []const u8 {
    const basename = std.fs.path.basename(buf);
    return if (opt_suffix) |suffix|
        if (std.mem.lastIndexOf(u8, basename, suffix)) |end_index|
            basename[0..end_index]
        else
            basename
    else
        basename;
}

test "basename no args" {
    try subcommands.testError(@This(), &.{}, .{}, "missing operand");
}

test "basename single" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    const ret = try subcommands.testExecute(@This(), &.{
        "hello/world",
    }, .{
        .stdout = stdout.writer(),
    });

    try std.testing.expect(ret == 0);
    try std.testing.expectEqualStrings("world\n", stdout.items);
}

test "basename multiple" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    const ret = try subcommands.testExecute(@This(), &.{
        "-a",
        "hello/world",
        "this/is/a/test",
        "a/b/c/d",
    }, .{
        .stdout = stdout.writer(),
    });

    try std.testing.expect(ret == 0);
    try std.testing.expectEqualStrings(
        \\world
        \\test
        \\d
        \\
    , stdout.items);
}

test "basename help" {
    try subcommands.testHelp(@This());
}

test "basename version" {
    try subcommands.testVersion(@This());
}

comptime {
    std.testing.refAllDecls(@This());
}
