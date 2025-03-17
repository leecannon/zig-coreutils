// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const Arg = @This();

raw: []const u8,
arg_type: ArgType,

pub fn init(value: []const u8, arg_type: ArgType) Arg {
    return .{ .raw = value, .arg_type = arg_type };
}

pub const ArgType = union(enum) {
    shorthand: Shorthand,
    longhand: []const u8,
    longhand_with_value: LonghandWithValue,
    positional: void,

    pub const LonghandWithValue = struct {
        longhand: []const u8,
        value: []const u8,
    };

    pub const Shorthand = struct {
        value: []const u8,
        index: usize = 1,

        pub fn next(self: *Shorthand) ?u8 {
            if (self.index >= self.value.len) return null;
            const char = self.value[self.index];
            self.index += 1;
            return char;
        }

        pub fn takeRest(self: *Shorthand) ?[]const u8 {
            if (self.index >= self.value.len) return null;
            const slice = self.value[self.index..];
            self.index = self.value.len;
            return slice;
        }

        pub fn reset(self: *Shorthand) void {
            self.index = 1;
        }
    };
};

pub const Iterator = union(enum) {
    args: std.process.ArgIterator,
    slice: struct {
        slice: []const [:0]const u8,
        index: usize = 0,
    },

    pub fn nextRaw(self: *Iterator) ?[:0]const u8 {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "raw next arg" });
        defer z.end();

        if (self.dispatchNext()) |arg| {
            @branchHint(.likely);
            z.text(arg);
            return arg;
        }

        return null;
    }

    pub fn next(self: *Iterator) ?Arg {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "next arg" });
        defer z.end();

        const current_arg = self.dispatchNext() orelse {
            @branchHint(.unlikely);
            return null;
        };

        z.text(current_arg);

        // the length checks in the below ifs allow '-' and '--' to fall through as positional arguments
        if (current_arg.len > 1 and current_arg[0] == '-') longhand_shorthand_blk: {
            if (current_arg.len > 2 and current_arg[1] == '-') {
                // longhand argument e.g. '--help'

                const entire_longhand = current_arg[2..];

                if (std.mem.indexOfScalar(u8, entire_longhand, '=')) |equal_index| {
                    // if equal_index is zero then the argument starts with '--=' which we do not count as a valid
                    // version of either longhand argument type nor a shorthand argument, so break out to make it positional
                    if (equal_index == 0) break :longhand_shorthand_blk;

                    const longhand = entire_longhand[0..equal_index];
                    const value = entire_longhand[equal_index + 1 ..];

                    log.debug("longhand argument with value \"{s}\" = \"{s}\"", .{ longhand, value });

                    return .init(
                        current_arg,
                        .{ .longhand_with_value = .{ .longhand = longhand, .value = value } },
                    );
                }

                log.debug("longhand argument \"{s}\"", .{entire_longhand});
                return .init(
                    current_arg,
                    .{ .longhand = entire_longhand },
                );
            }

            // this check allows '--' to fall through as a positional argument
            if (current_arg[1] != '-') {
                log.debug("shorthand argument \"{s}\"", .{current_arg});
                return .init(
                    current_arg,
                    .{ .shorthand = .{ .value = current_arg } },
                );
            }
        }

        log.debug("positional \"{s}\"", .{current_arg});
        return .init(
            current_arg,
            .positional,
        );
    }

    /// The only time `include_shorthand` should be false is if the command has it's own `-h` argument.
    pub fn nextWithHelpOrVersion(
        self: *Iterator,
        comptime include_shorthand: bool,
    ) error{ ShortHelp, FullHelp, Version }!?Arg {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "next arg with help/version" });
        defer z.end();

        var arg = self.next() orelse return null;

        switch (arg.arg_type) {
            .longhand => |longhand| {
                if (std.mem.eql(u8, longhand, "help")) {
                    return error.FullHelp;
                }
                if (std.mem.eql(u8, longhand, "version")) {
                    return error.Version;
                }
            },
            .shorthand => |*shorthand| {
                if (include_shorthand) {
                    while (shorthand.next()) |char| if (char == 'h') return error.ShortHelp;
                    shorthand.reset();
                }
            },
            else => {},
        }

        return arg;
    }

    inline fn dispatchNext(self: *Iterator) ?[:0]const u8 {
        switch (self.*) {
            .args => |*args| {
                @branchHint(if (builtin.is_test) .cold else .likely);
                return args.next();
            },
            .slice => |*slice| {
                @branchHint(if (builtin.is_test) .likely else .cold);
                if (slice.index < slice.slice.len) {
                    @branchHint(.likely);
                    defer slice.index += 1;
                    return slice.slice[slice.index];
                }
                return null;
            },
        }
    }
};

const log = std.log.scoped(.arg);

const builtin = @import("builtin");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
