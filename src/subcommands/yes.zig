// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const name = "yes";

pub const short_help =
    \\Usage: {0s} [STRING]...
    \\   or: {0s} OPTION
    \\
    \\Repeatedly output a line with all specified STRING(s), or 'y'.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `yes`
pub const extended_help = "";

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
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
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = name });
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
        stderr: std.io.AnyWriter,
        stdin: std.io.AnyReader,
        stdout: std.io.AnyWriter,
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

const log = std.log.scoped(.yes);
const shared = @import("../shared.zig");
const std = @import("std");
const subcommands = @import("../subcommands.zig");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
