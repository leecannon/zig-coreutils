const std = @import("std");
const subcommands = @import("subcommands.zig");
const build_options = @import("options");
const builtin = @import("builtin");

const log = std.log.scoped(.shared);

pub const tracy = @import("tracy.zig");

pub fn printHelp(comptime subcommand: type, io: anytype, exe_path: []const u8) u8 {
    const z = tracy.traceNamed(@src(), "print help");
    defer z.end();

    log.debug("printing help for " ++ subcommand.name, .{});
    io.stdout.print(subcommand.usage, .{exe_path}) catch {};
    return 0;
}

pub fn printVersion(comptime subcommand: type, io: anytype) u8 {
    const z = tracy.traceNamed(@src(), "print version");
    defer z.end();

    log.debug("printing version for " ++ subcommand.name, .{});
    io.stdout.print(version_string, .{subcommand.name}) catch {};
    return 0;
}

pub fn unableToWriteTo(comptime destination: []const u8, io: anytype, err: anyerror) void {
    io.stderr.writeAll("unable to write to " ++ destination ++ ": ") catch return;
    io.stderr.writeAll(@errorName(err)) catch return;
    io.stderr.writeByte('\n') catch return;
}

pub fn printInvalidUsage(comptime subcommand: type, io: anytype, exe_path: []const u8, error_message: []const u8) u8 {
    const z = tracy.traceNamed(@src(), "print error");
    defer z.end();
    z.addText(error_message);

    log.debug("printing error for " ++ subcommand.name, .{});

    output: {
        io.stderr.writeAll(exe_path) catch break :output;
        io.stderr.writeAll(": ") catch break :output;
        io.stderr.writeAll(error_message) catch break :output;
        io.stderr.writeAll("\nTry '") catch break :output;
        io.stderr.writeAll(exe_path) catch break :output;
        io.stderr.writeAll(" --help' for more information\n") catch break :output;
    }

    return 1;
}

pub fn printInvalidUsageAlloc(
    comptime subcommand: type,
    allocator: *std.mem.Allocator,
    io: anytype,
    exe_path: []const u8,
    comptime msg: []const u8,
    args: anytype,
) !u8 {
    const z = tracy.traceNamed(@src(), "print error alloc");
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer allocator.free(error_message);

    return printInvalidUsage(subcommand, io, exe_path, error_message);
}

pub const version_string = "{s} (zig-coreutils) " ++ build_options.version ++ "\nMIT License Copyright (c) 2021 Lee Cannon\n";

pub fn ArgIterator(comptime T: type) type {
    return struct {
        arg_iter: T,

        const Self = @This();

        pub fn init(arg_iter: T) Self {
            return .{ .arg_iter = arg_iter };
        }

        // BUG: this function should return `?[:0]const u8` but that hits a compiler bug
        // broken LLVM module found: Call parameter type does not match function signature!
        pub fn nextRaw(self: *Self) ?[]const u8 {
            const z = tracy.traceNamed(@src(), "raw next arg");
            defer z.end();

            if (self.arg_iter.nextPosix()) |arg| {
                z.addText(arg);
                return arg;
            }

            return null;
        }

        pub fn next(self: *Self) ?Arg {
            const z = tracy.traceNamed(@src(), "next arg");
            defer z.end();

            const current_arg = self.arg_iter.nextPosix() orelse return null;

            z.addText(current_arg);

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

                        return Arg.init(current_arg, .{ .longhand_with_value = .{ .longhand = longhand, .value = value } });
                    }

                    log.debug("longhand argument \"{s}\"", .{entire_longhand});
                    return Arg.init(current_arg, .{ .longhand = entire_longhand });
                }

                // this check allows '--' to fall through as a positional argument
                if (current_arg[1] != '-') {
                    log.debug("shorthand argument \"{s}\"", .{current_arg});
                    return Arg.init(current_arg, .{ .shorthand = .{ .value = current_arg } });
                }
            }

            log.debug("positional \"{s}\"", .{current_arg});
            return Arg.init(current_arg, .positional);
        }

        pub fn nextWithHelpOrVersion(self: *Self) error{ Help, Version }!?Arg {
            const z = tracy.traceNamed(@src(), "next arg with help/version");
            defer z.end();

            var arg = self.next() orelse return null;

            switch (arg.arg_type) {
                .longhand => |longhand| {
                    if (std.mem.eql(u8, longhand, "help")) {
                        return error.Help;
                    }
                    if (std.mem.eql(u8, longhand, "version")) {
                        return error.Version;
                    }
                },
                .shorthand => |*shorthand| {
                    while (shorthand.nextNoSkip()) |char| {
                        if (char == 'h') {
                            return error.Help;
                        }
                    }
                    shorthand.reset();
                },
                else => {},
            }

            return arg;
        }
    };
}

pub const Arg = struct {
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
                var index = self.index;
                defer self.index = index;

                while (index < self.value.len) {
                    defer index += 1;

                    const char = self.value[index];

                    if (char == 'h' or char == 'v') {
                        continue;
                    } else {
                        log.debug("\"{s}\" - shorthand sub-index {} is '{c}'", .{ self.value, index, char });
                    }

                    return char;
                }

                return null;
            }

            fn nextNoSkip(self: *Shorthand) ?u8 {
                if (self.index >= self.value.len) return null;
                const char = self.value[self.index];
                if (char == 'h' or char == 'v') log.debug("\"{s}\" - shorthand sub-index {} is '{c}'", .{ self.value, self.index, char });
                self.index += 1;
                return char;
            }

            pub fn reset(self: *Shorthand) void {
                self.index = 1;
            }
        };
    };
};

comptime {
    std.testing.refAllDecls(@This());
}
