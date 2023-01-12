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
//     fn nextWithHelpOrVersion(self: *Self, comptime include_shorthand: bool) !?shared.Arg,
//
//     fn nextRaw(self: *Self) ?[]const u8,
// }

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    system: zsw.System,
    exe_path: []const u8,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = system;

    const options = try parseArguments(allocator, io, args, exe_path);

    return performDirname(io, args, options);
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    exe_path: []const u8,
) !DirnameOptions {
    const z = shared.tracy.traceNamed(@src(), "parse arguments");
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
        .normal => shared.printInvalidUsage(@This(), io, exe_path, "missing operand"),
        .invalid_argument => |invalid_arg| switch (invalid_arg) {
            .slice => |slice| shared.printInvalidUsageAlloc(@This(), allocator, io, exe_path, "unrecognized option '{s}'", .{slice}),
            .character => |character| shared.printInvalidUsageAlloc(@This(), allocator, io, exe_path, "unrecognized option -- '{c}'", .{character}),
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
    const z = shared.tracy.traceNamed(@src(), "perform dirname");
    defer z.end();

    log.debug("performDirname called, options={}", .{options});

    const end_byte: u8 = if (options.zero) 0 else '\n';

    var opt_arg: ?[]const u8 = options.first_arg;

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

    try subcommands.testExecute(@This(), &.{
        "hello/world",
    }, .{
        .stdout = stdout.writer(),
    });

    try std.testing.expectEqualStrings("hello\n", stdout.items);
}

test "dirname multiple" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try subcommands.testExecute(@This(), &.{
        "hello/world",
        "this/is/a/test",
        "a/b/c/d",
    }, .{
        .stdout = stdout.writer(),
    });

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

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            if (@TypeOf(@field(T, decl.name)) == type) {
                switch (@typeInfo(@field(T, decl.name))) {
                    .Struct, .Enum, .Union, .Opaque => {
                        refAllDeclsRecursive(@field(T, decl.name));
                        _ = @field(T, decl.name);
                    },
                    .Type, .Fn => {
                        _ = @field(T, decl.name);
                    },
                    else => {},
                }
            }
        }
    }
}
