const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.yes);

pub const name = "yes";

pub const usage =
    \\Usage: {0s} [STRING]...
    \\   or: {0s} OPTION
    \\
    \\Repeatedly output a line with all specified STRING(s), or 'y'.
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
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

    _ = exe_path;
    _ = cwd;

    const string = try getString(allocator, args);
    defer if (shared.free_on_close) string.deinit(allocator);

    while (true) {
        io.stdout.writeAll(string.value) catch |err| {
            return shared.unableToWriteTo("stdout", io, err);
        };
    }
}

fn getString(allocator: std.mem.Allocator, args: anytype) !MaybeAllocatedString {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    var buffer = std.ArrayList(u8).init(allocator);
    defer if (shared.free_on_close) buffer.deinit();

    if (try args.nextWithHelpOrVersion(true)) |arg| {
        try buffer.appendSlice(arg.raw);
    } else {
        return MaybeAllocatedString.not_allocated("y\n");
    }

    while (args.nextRaw()) |arg| {
        try buffer.append(' ');
        try buffer.appendSlice(arg);
    }

    try buffer.append('\n');

    return MaybeAllocatedString.allocated(try buffer.toOwnedSlice());
}

const MaybeAllocatedString = MaybeAllocated([]const u8, freeSlice);

fn freeSlice(self: []const u8, allocator: std.mem.Allocator) void {
    allocator.free(self);
}

fn MaybeAllocated(comptime T: type, comptime dealloc: fn (self: T, allocator: std.mem.Allocator) void) type {
    return struct {
        is_allocated: bool,
        value: T,

        pub fn allocated(value: T) @This() {
            return .{
                .is_allocated = true,
                .value = value,
            };
        }

        pub fn not_allocated(value: T) @This() {
            return .{
                .is_allocated = false,
                .value = value,
            };
        }

        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            if (self.is_allocated) {
                dealloc(self.value, allocator);
            }
        }
    };
}

test "yes help" {
    try subcommands.testHelp(@This(), true);
}

test "yes version" {
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
