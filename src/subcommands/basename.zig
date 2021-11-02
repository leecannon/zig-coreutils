const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.basename);

pub const name = "basename";

pub const usage =
    \\Usage: {0s} NAME [SUFFIX]
    \\   or: {0s} OPTION... NAME...
    \\Print NAME with any leading directory components removed.
    \\If specified, also remove a trailing SUFFIX.
    \\
    \\Mandatory arguments to long options are mandatory for short options too.
    \\  -a, --multiple       support multiple arguments and treat each as a NAME
    \\  -s, --suffix=SUFFIX  remove a trailing SUFFIX; implies -a
    \\  -z, --zero           end each output line with NUL, not newline
    \\      --help     display this help and exit
    \\      --version  output version information and exit
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
//
//     fn nextRaw(self: *Self) !?shared.WrappedString,
// }

pub fn execute(allocator: *std.mem.Allocator, io: anytype, args: anytype, exe_path: []const u8) !u8 {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    var arg: shared.Arg = (try args.nextWithHelpOrVersion()) orelse {
        return shared.printInvalidUsage(@This(), io, exe_path, "missing operand");
    };
    defer arg.deinit(allocator);

    var zero: bool = false;
    var multiple: bool = false;
    var opt_multiple_suffix: ?shared.WrappedString = null;
    defer if (opt_multiple_suffix) |multiple_suffix| multiple_suffix.deinit(allocator);

    while (true) {
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
                        "invalid option '--{s}'",
                        .{longhand},
                    );
                }
            },
            .longhand_with_value => |longhand_with_value| {
                if (std.mem.eql(u8, longhand_with_value.longhand, "suffix")) {
                    multiple = true;
                    opt_multiple_suffix = try longhand_with_value.dupeValue(allocator);
                    log.debug("got suffix longhand with value = {s}", .{longhand_with_value.value});
                } else {
                    return try shared.printInvalidUsageAlloc(
                        @This(),
                        allocator,
                        io,
                        exe_path,
                        "invalid option '{s}'",
                        .{longhand_with_value.value},
                    );
                }
            },
            .positional => {
                if (multiple) {
                    return try multipleArguments(
                        allocator,
                        io,
                        args,
                        arg.wrapped_str,
                        zero,
                        opt_multiple_suffix,
                    );
                }
                return try singleArgument(allocator, io, args, exe_path, arg.wrapped_str.value, zero);
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
                        opt_multiple_suffix = (try args.nextRaw()) orelse {
                            return shared.printInvalidUsage(
                                @This(),
                                io,
                                exe_path,
                                "option requires an argument -- 's'",
                            );
                        };
                        multiple = true;
                        log.debug("got suffix shorthand with value = {s}", .{(opt_multiple_suffix orelse unreachable).value});
                    } else {
                        return try shared.printInvalidUsageAlloc(
                            @This(),
                            allocator,
                            io,
                            exe_path,
                            "invalid option -- '{c}'",
                            .{char},
                        );
                    }
                }
            },
        }

        arg.deinit(allocator);
        arg = (try args.next()) orelse {
            return shared.printInvalidUsage(@This(), io, exe_path, "missing operand");
        };
    }

    return 0;
}

pub fn singleArgument(
    allocator: *std.mem.Allocator,
    io: anytype,
    args: anytype,
    exe_path: []const u8,
    first_arg: []const u8,
    zero: bool,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "single argument");
    defer z.end();
    z.addText(first_arg);

    const opt_suffix: ?shared.WrappedString = blk: {
        const suffix_zone = shared.tracy.traceNamed(@src(), "get suffix");
        defer suffix_zone.end();

        const arg = (try args.nextRaw()) orelse break :blk null;

        if (try args.nextRaw()) |additional_arg| {
            defer {
                additional_arg.deinit(allocator);
                arg.deinit(allocator);
            }

            return try shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "extra operand '{s}'",
                .{additional_arg.value},
            );
        }

        suffix_zone.addText(arg.value);

        break :blk arg;
    };

    log.info("singleArgument called, first_arg='{s}', zero={}, suffix='{}'", .{ first_arg, zero, opt_suffix });

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

pub fn multipleArguments(
    allocator: *std.mem.Allocator,
    io: anytype,
    args: anytype,
    first_arg: shared.WrappedString,
    zero: bool,
    opt_suffix: ?shared.WrappedString,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "multiple arguments");
    defer z.end();

    log.info("multipleArguments called, first_arg='{}', zero={}, suffix='{}'", .{ first_arg, zero, opt_suffix });

    var opt_arg: ?shared.WrappedString = first_arg;
    var is_first_arg: bool = false;

    const end_byte: u8 = if (zero) 0 else '\n';

    while (opt_arg) |arg| : (opt_arg = try args.nextRaw()) {
        const argument_zone = shared.tracy.traceNamed(@src(), "process arg");
        defer argument_zone.end();
        argument_zone.addText(arg.value);

        const basename = getBasename(arg.value, opt_suffix);
        log.debug("got basename: '{s}'", .{basename});

        io.stdout.writeAll(basename) catch |err| {
            shared.unableToWriteTo("stdout", io, err);
            return 1;
        };

        io.stdout.writeByte(end_byte) catch |err| {
            shared.unableToWriteTo("stdout", io, err);
            return 1;
        };

        if (is_first_arg) {
            is_first_arg = false;
        } else {
            arg.deinit(allocator);
        }
    }

    return 0;
}

fn getBasename(buf: []const u8, opt_suffix: ?shared.WrappedString) []const u8 {
    const basename = std.fs.path.basename(buf);
    return if (opt_suffix) |suffix|
        if (std.mem.lastIndexOf(u8, basename, suffix.value)) |end_index|
            basename[0..end_index]
        else
            basename
    else
        basename;
}

test "basename no args" {
    try subcommands.testError(@This(), &.{}, .{}, "missing operand");
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
