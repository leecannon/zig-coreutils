const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.uname);

pub const name = "uname";

pub const short_help =
    \\Usage: {0s} [OPTION]...
    \\
    \\Print system information. With no OPTION same as -s.
    \\
    \\     -a, --all                print all information, in the following order,
    \\                                except omit -p and -i if unknown.
    \\     -s, --kernel-name        print the kernel name
    \\     -n, --nodename           print the network node hostname
    \\     -r, --kernel-release     print the kernel release
    \\     -v, --kernel-version     print the kernel version
    \\     -m, --machine            print the machine hardware name
    \\     -p, --processor          print the processor type
    \\     -i, --hardware-platform  print the hardware platform
    \\     -o, --operating-system   print the operating system
    \\     -h, --help               display this help and exit
    \\     --version                output version information and exit
    \\
;

// No examples provided for `uname`
// TODO: Should there be?
pub const extended_help = "";

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
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    const options = try parseArguments(allocator, io, args, exe_path);

    return performUname(allocator, io, args, cwd, options);
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    exe_path: []const u8,
) !UnameOptions {
    const z = shared.tracy.traceNamed(@src(), "parse arguments");
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(true);

    var options: UnameOptions = .{};

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

                if (std.mem.eql(u8, longhand, "all")) {
                    options.kernel_name = true;
                    options.node_name = true;
                    options.kernel_release = true;
                    options.kernel_version = true;
                    options.machine = true;
                    options.processor = true;
                    options.hardware_platform = true;
                    options.os = true;
                    log.debug("got do all longhand", .{});
                } else if (std.mem.eql(u8, longhand, "kernel-name")) {
                    options.kernel_name = true;
                    log.debug("got kernel name longhand", .{});
                } else if (std.mem.eql(u8, longhand, "nodename")) {
                    options.node_name = true;
                    log.debug("got node name longhand", .{});
                } else if (std.mem.eql(u8, longhand, "kernel-release")) {
                    options.kernel_release = true;
                    log.debug("got kernel release longhand", .{});
                } else if (std.mem.eql(u8, longhand, "kernel-version")) {
                    options.kernel_version = true;
                    log.debug("got kernel version longhand", .{});
                } else if (std.mem.eql(u8, longhand, "machine")) {
                    options.machine = true;
                    log.debug("got machine longhand", .{});
                } else if (std.mem.eql(u8, longhand, "processor")) {
                    options.processor = true;
                    log.debug("got processor longhand", .{});
                } else if (std.mem.eql(u8, longhand, "hardware-platform")) {
                    options.hardware_platform = true;
                    log.debug("got hardware platform longhand", .{});
                } else if (std.mem.eql(u8, longhand, "operating-system")) {
                    options.os = true;
                    log.debug("got operating system longhand", .{});
                } else {
                    state = .{ .invalid_argument = .{ .slice = longhand } };
                    break;
                }
            },
            .longhand_with_value => |longhand_with_value| {
                if (state != .normal) break;
                state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                break;
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (state != .normal) break;

                    switch (char) {
                        'a' => {
                            options.kernel_name = true;
                            options.node_name = true;
                            options.kernel_release = true;
                            options.kernel_version = true;
                            options.machine = true;
                            options.processor = true;
                            options.hardware_platform = true;
                            options.os = true;
                            log.debug("got all shorthand", .{});
                        },
                        's' => {
                            options.kernel_name = true;
                            log.debug("got kernel name shorthand", .{});
                        },
                        'n' => {
                            options.node_name = true;
                            log.debug("got node name shorthand", .{});
                        },
                        'r' => {
                            options.kernel_release = true;
                            log.debug("got kernel release shorthand", .{});
                        },
                        'v' => {
                            options.kernel_version = true;
                            log.debug("got kernel version shorthand", .{});
                        },
                        'm' => {
                            options.machine = true;
                            log.debug("got machine shorthand", .{});
                        },
                        'p' => {
                            options.processor = true;
                            log.debug("got processor shorthand", .{});
                        },
                        'i' => {
                            options.hardware_platform = true;
                            log.debug("got hardware platform shorthand", .{});
                        },
                        'o' => {
                            options.os = true;
                            log.debug("gotoperating system shorthand", .{});
                        },
                        else => {
                            state = .{ .invalid_argument = .{ .character = char } };
                            break;
                        },
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

fn performUname(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    cwd: std.fs.Dir,
    options: UnameOptions,
) !void {
    _ = cwd;
    _ = args;
    _ = io;
    _ = allocator;

    const z = shared.tracy.traceNamed(@src(), "perform uname");
    defer z.end();

    log.debug("performUname called, options={}", .{options});
}

const UnameOptions = struct {
    kernel_name: bool = true,
    node_name: bool = false,
    kernel_release: bool = false,
    kernel_version: bool = false,
    machine: bool = false,
    processor: bool = false,
    hardware_platform: bool = false,
    os: bool = false,
};

test "uname no args" {
    try subcommands.testExecute(@This(), &.{}, .{});
}

test "uname help" {
    try subcommands.testHelp(@This(), true);
}

test "uname version" {
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
