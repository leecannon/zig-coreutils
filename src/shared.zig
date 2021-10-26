const std = @import("std");
const subcommands = @import("subcommands.zig");
const options = @import("options");

const log = std.log.scoped(.shared);

pub fn printHelp(comptime subcommand: type, io: anytype, exe_path: []const u8) u8 {
    log.debug("printing help for " ++ subcommand.name, .{});
    io.stdout.print(subcommand.usage, .{exe_path}) catch {};
    return 0;
}

pub fn printVersion(comptime subcommand: type, io: anytype) u8 {
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

pub const ArgIterator = struct {
    input: []const []const u8,
    index: usize = 0,

    sub_index: ?usize = null,

    pub fn init(input: []const []const u8) ArgIterator {
        return .{ .input = input };
    }

    pub fn next(self: *ArgIterator) ?Arg {
        if (self.index >= self.input.len) return null;

        const current_arg = self.input[self.index];

        if (self.sub_index) |sub_index| {
            const char = current_arg[sub_index];

            self.sub_index = sub_index + 1;

            if (self.sub_index == current_arg.len) {
                self.sub_index = null;
                self.index += 1;
                log.debug("\"{s}\" - shorthand sub-index {} is '{c}' - last shorthand in this group", .{ current_arg, sub_index, char });
            } else {
                log.debug("\"{s}\" - shorthand sub-index {} is '{c}'", .{ current_arg, sub_index, char });
            }

            return Arg{ .shorthand = char };
        }

        // the length checks in the below ifs allow '-' and '--' to fall through as positional arguments
        if (current_arg.len > 1 and current_arg[0] == '-') {
            if (current_arg.len > 2 and current_arg[1] == '-') {
                // longhand argument e.g. '--help'

                const longhand = current_arg[2..];

                log.debug("longhand argument \"{s}\"", .{longhand});

                self.index += 1;
                return Arg{ .longhand = longhand };
            }

            // this check allows '--' to fall through as a positional argument
            if (current_arg[1] != '-') {
                // one or more shorthand aruments e.g. '-h' or '-abc'
                const char = current_arg[1];

                // If there are multiple shorthand arguments joined together e.g. '-abc' prime `sub_index`
                // if there are not move to the next argument
                if (current_arg.len > 2) {
                    self.sub_index = 2;
                    log.debug("\"{s}\" - shorthand sub-index 1 is '{c}' - first shorthand in this group", .{ current_arg, char });
                } else {
                    self.index += 1;
                    log.debug("\"{s}\" - shorthand is '{c}' - only shorthand in this group", .{ current_arg, char });
                }

                return Arg{ .shorthand = char };
            }
        }

        log.debug("positional \"{s}\"", .{current_arg});
        self.index += 1;
        return Arg{ .positional = current_arg };
    }

    pub const Arg = union(enum) {
        shorthand: u8,
        longhand: []const u8,
        positional: []const u8,
    };
};

comptime {
    std.testing.refAllDecls(@This());
}
