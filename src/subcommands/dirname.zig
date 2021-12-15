const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const zsw = @import("zsw");

const log = std.log.scoped(.dirname);

pub const name = "dirname";

pub const usage =
    \\Usage: {0s} [OPTION] NAME...
    \\
    \\Print each NAME with its last non-slash components and trailing slashes removed.
    \\If NAME contains no slashes outputs '.' (the current directory).
    \\
    \\  -z, --zero     end each output line with NUL, not newline
    \\      --help     display this help and exit
    \\      --version  output version information and exit
    \\
;

// Usage: dirname [OPTION] NAME...
// Output each NAME with its last non-slash component and trailing slashes
// removed; if NAME contains no /'s, output '.' (meaning the current directory).

//   -z, --zero     end each output line with NUL, not newline
//       --help     display this help and exit
//       --version  output version information and exit

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

    var zero: bool = false;

    while (opt_arg) |*arg| : (opt_arg = args.next()) {
        switch (arg.arg_type) {
            .longhand => |longhand| {
                if (std.mem.eql(u8, longhand, "zero")) {
                    zero = true;
                    log.debug("got zero longhand", .{});
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
            .longhand_with_value => {
                return try shared.printInvalidUsageAlloc(
                    @This(),
                    allocator,
                    io,
                    exe_path,
                    "unrecognized option '{s}'",
                    .{arg.raw},
                );
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (char == 'z') {
                        zero = true;
                        log.debug("got zero shorthand", .{});
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
            .positional => {
                return try performDirname(io, args, arg.raw, zero);
            },
        }
    }

    return shared.printInvalidUsage(@This(), io, exe_path, "missing operand");
}

fn performDirname(
    io: anytype,
    args: anytype,
    first_arg: []const u8,
    zero: bool,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "perform dirname");
    defer z.end();

    log.info("performDirname called, first_arg='{s}', zero={}", .{ first_arg, zero });

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

        const dirname = getDirname(arg);
        log.debug("got dirname: '{s}'", .{dirname});

        io.stdout.writeAll(dirname) catch |err| {
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

fn getDirname(buf: []const u8) []const u8 {
    if (std.fs.path.dirname(buf)) |dir| return dir;
    return ".";
}

test "basename no args" {
    try subcommands.testError(@This(), &.{}, .{}, "missing operand");
}

test "dirname help" {
    try subcommands.testHelp(@This());
}

test "dirname version" {
    try subcommands.testVersion(@This());
}

comptime {
    std.testing.refAllDecls(@This());
}
