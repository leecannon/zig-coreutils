const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.false);

pub const name = "false";

pub const short_help =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Exit with a status code indicating failure.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `false`
pub const extended_help = "";

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = io;
    _ = exe_path;
    _ = cwd;
    _ = allocator;

    // Only the first argument is checked for help or version
    _ = try args.nextWithHelpOrVersion(true);

    // FIXME: This is weird, is this acceptable to allow the other subcommands to not have to worry about u8 return value?
    return error.AlreadyHandled;
}

test "false no args" {
    try std.testing.expectError(
        error.AlreadyHandled,
        subcommands.testExecute(
            @This(),
            &.{},
            .{},
        ),
    );
}

test "false ignores args" {
    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    try std.testing.expectError(
        error.AlreadyHandled,
        subcommands.testExecute(
            @This(),
            &.{ "these", "arguments", "are", "ignored" },
            .{},
        ),
    );

    try std.testing.expectEqualStrings("", stdout.items);
}

test "false help" {
    try subcommands.testHelp(@This(), true);
}

test "false version" {
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

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
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
