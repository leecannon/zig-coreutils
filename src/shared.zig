const std = @import("std");
const subcommands = @import("subcommands.zig");
const build_options = @import("options");
const builtin = @import("builtin");

pub const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
pub const free_on_close = is_debug_or_test or tracy.enable;

const log = std.log.scoped(.shared);

pub const tracy = @import("tracy.zig");

pub fn printHelp(comptime subcommand: type, io: anytype, exe_path: []const u8) void {
    const z = tracy.traceNamed(@src(), "print help");
    defer z.end();

    log.debug(comptime "printing help for " ++ subcommand.name, .{});
    io.stdout.print(subcommand.usage, .{exe_path}) catch {};
}

pub fn printVersion(comptime subcommand: type, io: anytype) void {
    const z = tracy.traceNamed(@src(), "print version");
    defer z.end();

    log.debug(comptime "printing version for " ++ subcommand.name, .{});
    io.stdout.print(version_string, .{subcommand.name}) catch {};
}

pub fn unableToWriteTo(comptime destination: []const u8, io: anytype, err: anyerror) error{AlreadyHandled} {
    blk: {
        io.stderr.writeAll(comptime "unable to write to " ++ destination ++ ": ") catch break :blk;
        io.stderr.writeAll(@errorName(err)) catch break :blk;
        io.stderr.writeByte('\n') catch break :blk;
    }
    return error.AlreadyHandled;
}

pub fn printError(comptime subcommand: type, io: anytype, error_message: []const u8) error{AlreadyHandled} {
    const z = tracy.traceNamed(@src(), "print error");
    defer z.end();
    z.addText(error_message);

    log.debug(comptime "printing error for " ++ subcommand.name, .{});

    output: {
        io.stderr.writeAll(subcommand.name) catch break :output;
        io.stderr.writeAll(": ") catch break :output;
        io.stderr.writeAll(error_message) catch break :output;
        io.stderr.writeByte('\n') catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printErrorAlloc(
    comptime subcommand: type,
    allocator: std.mem.Allocator,
    io: anytype,
    comptime msg: []const u8,
    args: anytype,
) error{ OutOfMemory, AlreadyHandled } {
    const z = tracy.traceNamed(@src(), "print error alloc");
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer if (free_on_close) allocator.free(error_message);

    return printError(subcommand, io, error_message);
}

pub fn printInvalidUsage(comptime subcommand: type, io: anytype, exe_path: []const u8, error_message: []const u8) error{AlreadyHandled} {
    const z = tracy.traceNamed(@src(), "print invalid usage");
    defer z.end();
    z.addText(error_message);

    log.debug(comptime "printing error for " ++ subcommand.name, .{});

    output: {
        io.stderr.writeAll(exe_path) catch break :output;
        io.stderr.writeAll(": ") catch break :output;
        io.stderr.writeAll(error_message) catch break :output;
        io.stderr.writeAll("\nTry '") catch break :output;
        io.stderr.writeAll(exe_path) catch break :output;
        io.stderr.writeAll(" --help' for more information\n") catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printInvalidUsageAlloc(
    comptime subcommand: type,
    allocator: std.mem.Allocator,
    io: anytype,
    exe_path: []const u8,
    comptime msg: []const u8,
    args: anytype,
) error{ OutOfMemory, AlreadyHandled } {
    const z = tracy.traceNamed(@src(), "print invalid usage alloc");
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer if (free_on_close) allocator.free(error_message);

    return printInvalidUsage(subcommand, io, exe_path, error_message);
}

pub fn mapFile(
    comptime subcommand: type,
    allocator: std.mem.Allocator,
    io: anytype,
    cwd: std.fs.Dir,
    path: []const u8,
) error{ AlreadyHandled, OutOfMemory }!MappedFile {
    const file = cwd.openFile(path, .{}) catch {
        return printErrorAlloc(
            subcommand,
            allocator,
            io,
            "unable to open '{s}'",
            .{path},
        );
    };
    errdefer if (free_on_close) file.close();

    const stat = file.stat() catch |err| {
        return printErrorAlloc(
            subcommand,
            allocator,
            io,
            "unable to stat '{s}': {s}",
            .{ path, @errorName(err) },
        );
    };

    if (stat.size == 0) {
        return .{
            .file = file,
            .file_contents = &.{},
        };
    }

    const file_contents = std.os.mmap(
        null,
        stat.size,
        std.os.PROT.READ,
        std.os.MAP.PRIVATE,
        file.handle,
        0,
    ) catch |err| {
        return printErrorAlloc(
            subcommand,
            allocator,
            io,
            "unable to map '{s}': {s}",
            .{ path, @errorName(err) },
        );
    };

    return .{
        .file = file,
        .file_contents = file_contents,
    };
}

pub const MappedFile = struct {
    file: std.fs.File,
    file_contents: []align(std.mem.page_size) const u8,

    pub fn close(self: MappedFile) void {
        if (free_on_close) {
            if (self.file_contents.len != 0) std.os.munmap(self.file_contents);
            self.file.close();
        }
    }
};

pub const version_string = "{s} (zig-coreutils) " ++ build_options.version ++ "\nMIT License Copyright (c) 2021-2023 Lee Cannon\n";

pub fn ArgIterator(comptime T: type) type {
    return struct {
        arg_iter: T,

        const Self = @This();

        pub fn init(arg_iter: T) Self {
            return .{ .arg_iter = arg_iter };
        }

        pub fn nextRaw(self: *Self) ?[:0]const u8 {
            const z = tracy.traceNamed(@src(), "raw next arg");
            defer z.end();

            if (self.arg_iter.next()) |arg| {
                z.addText(arg);
                return arg;
            }

            return null;
        }

        pub fn next(self: *Self) ?Arg {
            const z = tracy.traceNamed(@src(), "next arg");
            defer z.end();

            const current_arg = self.arg_iter.next() orelse return null;

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

        /// The only time `include_shorthand` should be false is if the subcommand has it's own `-h` argument.
        pub fn nextWithHelpOrVersion(self: *Self, comptime include_shorthand: bool) error{ Help, Version }!?Arg {
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
                    if (include_shorthand) {
                        while (shorthand.next()) |char| if (char == 'h') return error.Help;
                        shorthand.reset();
                    }
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
};

pub fn passwdFileIterator(passwd_file_contents: []const u8) PasswdFileIterator {
    return .{
        .passwd_file_contents = passwd_file_contents,
    };
}

pub const PasswdFileIterator = struct {
    index: usize = 0,
    passwd_file_contents: []const u8,

    pub const Entry = struct {
        user_name: []const u8,
        user_id: []const u8,
        primary_group_id: []const u8,
    };

    /// The returned `Entry` is invalidated on any subsequent call to `next`
    pub fn next(
        self: *PasswdFileIterator,
        comptime subcommand: type,
        io: anytype,
    ) error{AlreadyHandled}!?Entry {
        if (self.index >= self.passwd_file_contents.len) return null;

        const remaining = self.passwd_file_contents[self.index..];

        const line_length = std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len - 1;

        self.index += line_length + 1;

        var column_iter = std.mem.tokenize(u8, remaining[0..line_length], ":");

        const user_name = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/passwd' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/passwd' is invalid");

        const user_id_slice = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/passwd' is invalid");

        const primary_group_id_slice = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/passwd' is invalid");

        return .{
            .user_name = user_name,
            .user_id = user_id_slice,
            .primary_group_id = primary_group_id_slice,
        };
    }
};

pub fn groupFileIterator(group_file_contents: []const u8) GroupFileIterator {
    return .{
        .group_file_contents = group_file_contents,
    };
}

pub const GroupFileIterator = struct {
    index: usize = 0,
    group_file_contents: []const u8,

    pub const Entry = struct {
        group_name: []const u8,
        group_id: []const u8,
        members_slice: ?[]const u8,

        pub fn iterateMembers(self: *const Entry) std.mem.TokenIterator(u8) {
            return std.mem.tokenize(u8, self.members_slice orelse &[_]u8{}, ",");
        }
    };

    /// The returned `Entry` is invalidated on any subsequent call to `next`
    pub fn next(
        self: *GroupFileIterator,
        comptime subcommand: type,
        io: anytype,
    ) error{AlreadyHandled}!?Entry {
        if (self.index >= self.group_file_contents.len) return null;

        const remaining = self.group_file_contents[self.index..];

        const line_length = std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len - 1;

        self.index += line_length + 1;

        var column_iter = std.mem.tokenize(u8, remaining[0..line_length], ":");

        const group_name = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/group' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/group' is invalid");

        const group_id_slice = column_iter.next() orelse
            return printError(subcommand, io, "format of '/etc/group' is invalid");

        return .{
            .group_name = group_name,
            .group_id = group_id_slice,
            .members_slice = column_iter.next(),
        };
    }
};

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
