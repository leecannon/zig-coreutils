const std = @import("std");
const subcommands = @import("subcommands.zig");
const options = @import("options");
const builtin = @import("builtin");

const log = std.log.scoped(.shared);

pub const tracy = @import("tracy.zig");

pub fn printHelp(comptime subcommand: type, io: anytype, exe_path: []const u8) u8 {
    const z = tracy.traceNamed(@src(), "help");
    defer z.end();

    log.debug("printing help for " ++ subcommand.name, .{});
    io.stdout.print(subcommand.usage, .{exe_path}) catch {};
    return 0;
}

pub fn printVersion(comptime subcommand: type, io: anytype) u8 {
    const z = tracy.traceNamed(@src(), "version");
    defer z.end();

    log.debug("printing version for " ++ subcommand.name, .{});
    io.stdout.print(version_string, .{subcommand.name}) catch {};
    return 0;
}

const version_string = "{s} (zig-coreutils) " ++ options.version ++ "\nMIT License Copyright (c) 2021 Lee Cannon\n";

pub fn testHelp(comptime subcommand: type) !void {
    const expected = try std.fmt.allocPrint(std.testing.allocator, subcommand.usage, .{subcommand.name});
    defer std.testing.allocator.free(expected);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            subcommand,
            &.{"--help"},
            .{ .stdout = out.writer() },
        ),
    );

    try std.testing.expectEqualStrings(expected, out.items);

    out.deinit();
    out = std.ArrayList(u8).init(std.testing.allocator);

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            subcommand,
            &.{"-h"},
            .{ .stdout = out.writer() },
        ),
    );

    try std.testing.expectEqualStrings(expected, out.items);
}

pub fn testVersion(comptime subcommand: type) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            subcommand,
            &.{"--version"},
            .{ .stdout = out.writer() },
        ),
    );

    const expected = try std.fmt.allocPrint(std.testing.allocator, version_string, .{subcommand.name});
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, out.items);
}

pub fn ArgIterator(comptime T: type) type {
    return struct {
        arg_iter: T,

        sub_arg: ?[]const u8 = null,
        sub_index: usize = 1,

        const Self = @This();

        pub fn init(arg_iter: T) Self {
            return .{ .arg_iter = arg_iter };
        }

        pub fn deinit(self: *Self, allocator: *std.mem.Allocator) void {
            if (builtin.os.tag == .windows) {
                if (self.sub_arg) |sub_arg| {
                    allocator.free(sub_arg);
                }
            }
        }

        pub fn next(self: *Self, allocator: *std.mem.Allocator) error{ UnableToParseArguments, Help, Version }!?Arg {
            const z = tracy.traceNamed(@src(), "next argument");
            defer z.end();

            if (self.sub_arg) |sub_arg| {
                const sub_index = self.sub_index;
                const new_index = sub_index + 1;

                const char = sub_arg[sub_index];

                if (new_index == sub_arg.len) {
                    log.debug("\"{s}\" - shorthand sub-index {} is '{c}' - last shorthand in this group", .{ sub_arg, sub_index, char });
                    if (builtin.os.tag == .windows) {
                        allocator.free(sub_arg);
                    }
                    self.sub_arg = null;
                } else {
                    log.debug("\"{s}\" - shorthand sub-index {} is '{c}'", .{ sub_arg, sub_index, char });
                    self.sub_index = new_index;
                }

                return Arg{ .shorthand = char };
            }

            const current_arg = if (builtin.os.tag == .windows)
                (self.arg_iter.next(allocator) orelse return null) catch return error.UnableToParseArguments
            else
                self.arg_iter.nextPosix() orelse return null;

            // the length checks in the below ifs allow '-' and '--' to fall through as positional arguments
            if (current_arg.len > 1 and current_arg[0] == '-') longhand_shorthand_blk: {
                if (current_arg.len > 2 and current_arg[1] == '-') {
                    // longhand argument e.g. '--help'

                    const entire_longhand = current_arg[2.. :0];

                    if (std.mem.indexOfScalar(u8, entire_longhand, '=')) |equal_index| {
                        // if equal_index is zero then the argument starts with '--=' which we do not count as a valid
                        // version of either longhand argument type nor a shorthand argument, so break out to make it positional
                        if (equal_index == 0) break :longhand_shorthand_blk;

                        const longhand = entire_longhand[0..equal_index];
                        const value = entire_longhand[equal_index + 1 ..];

                        log.debug("longhand argument with value \"{s}\" = \"{s}\"", .{ longhand, value });

                        return Arg{ .longhand_with_value = .{ .longhand = longhand, .value = value } };
                    }

                    log.debug("longhand argument \"{s}\"", .{entire_longhand});

                    if (std.mem.eql(u8, entire_longhand, "help")) {
                        return error.Help;
                    }
                    if (std.mem.eql(u8, entire_longhand, "version")) {
                        return error.Version;
                    }

                    return Arg{ .longhand = entire_longhand };
                }

                // this check allows '--' to fall through as a positional argument
                if (current_arg[1] != '-') {
                    // one or more shorthand aruments e.g. '-h' or '-abc'
                    const char = current_arg[1];

                    // If there are multiple shorthand arguments joined together e.g. '-abc' prime `sub_index`
                    // if there are not move to the next argument
                    if (current_arg.len > 2) {
                        self.sub_index = 2;
                        self.sub_arg = current_arg;
                        log.debug("\"{s}\" - shorthand sub-index 1 is '{c}' - first shorthand in this group", .{ current_arg, char });
                    } else {
                        log.debug("\"{s}\" - shorthand is '{c}' - only shorthand in this group", .{ current_arg, char });
                        if (builtin.os.tag == .windows) {
                            allocator.free(current_arg);
                        }
                    }

                    if (char == 'h') {
                        return error.Help;
                    }

                    return Arg{ .shorthand = char };
                }
            }

            log.debug("positional \"{s}\"", .{current_arg});
            return Arg{ .positional = current_arg };
        }
    };
}

pub const Arg = union(enum) {
    shorthand: u8,
    longhand: [:0]const u8,
    longhand_with_value: LonghandWithValue,
    positional: [:0]const u8,

    pub const LonghandWithValue = struct {
        longhand: []const u8,
        value: []const u8,
    };

    pub fn deinit(self: Arg, allocator: *std.mem.Allocator) void {
        if (builtin.os.tag == .windows) {
            switch (self) {
                .longhand => |longhand| {
                    // we need to do this ptr arithmetic as for longhand args the starting '--' is not included
                    const corrected_ptr = (longhand.ptr - 2)[0..(2 + longhand.len) :0];
                    allocator.free(corrected_ptr);
                },
                .longhand_with_value => |longhand_with_value| {
                    const corrected_ptr = (longhand_with_value.longhand.ptr - 2)[0..(2 + longhand_with_value.longhand.len + 1 + longhand_with_value.value.len) :0];
                    allocator.free(corrected_ptr);
                },
                .positional => |positional| allocator.free(positional),
                .shorthand => {},
            }
        }
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
