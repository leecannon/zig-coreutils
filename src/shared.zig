// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const base_version_string = "zig-coreutils " ++ options.version ++ "\nMIT License Copyright (c) 2025 Lee Cannon\n";
pub const version_string = "{s} - " ++ base_version_string;
pub const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
pub const free_on_close = is_debug_or_test or options.trace;

pub fn printShortHelp(comptime command: type, io: IO, exe_path: []const u8) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print short help" });
    defer z.end();

    log.debug(comptime "printing short help for " ++ command.name, .{});
    io.stdout.print(command.short_help, .{exe_path}) catch |err|
        return unableToWriteTo("stdout", io, err);
}

pub fn printFullHelp(comptime command: type, io: IO, exe_path: []const u8) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print full help" });
    defer z.end();

    log.debug(comptime "printing full help for " ++ command.name, .{});
    if (@hasDecl(command, "extended_help")) {
        io.stdout.print(
            comptime command.short_help ++ "\n" ++ command.extended_help,
            .{exe_path},
        ) catch |err|
            return unableToWriteTo("stdout", io, err);
    } else {
        io.stdout.print(comptime command.short_help, .{exe_path}) catch |err|
            return unableToWriteTo("stdout", io, err);
    }
}

pub fn printVersion(comptime command: type, io: IO) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print version" });
    defer z.end();

    log.debug(comptime "printing version for " ++ command.name, .{});
    io.stdout.print(version_string, .{command.name}) catch |err|
        return unableToWriteTo("stdout", io, err);
}

pub fn unableToWriteTo(comptime destination: []const u8, io: IO, err: anyerror) error{AlreadyHandled} {
    @branchHint(.cold);

    blk: {
        io.stderr.writeAll(comptime "unable to write to " ++ destination ++ ": ") catch break :blk;
        io.stderr.writeAll(@errorName(err)) catch break :blk;
        io.stderr.writeByte('\n') catch break :blk;
    }
    return error.AlreadyHandled;
}

pub fn printError(comptime command: type, io: IO, error_message: []const u8) error{AlreadyHandled} {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print error" });
    defer z.end();
    z.text(error_message);

    log.debug(comptime "printing error for " ++ command.name, .{});

    output: {
        io.stderr.writeAll(command.name) catch break :output;
        io.stderr.writeAll(": ") catch break :output;
        io.stderr.writeAll(error_message) catch break :output;
        io.stderr.writeByte('\n') catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printErrorAlloc(
    comptime command: type,
    allocator: std.mem.Allocator,
    io: IO,
    comptime msg: []const u8,
    args: anytype,
) error{ OutOfMemory, AlreadyHandled } {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print error alloc" });
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer if (free_on_close) allocator.free(error_message);

    return printError(command, io, error_message);
}

pub fn printInvalidUsage(
    comptime command: type,
    io: IO,
    exe_path: []const u8,
    error_message: []const u8,
) error{AlreadyHandled} {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print invalid usage" });
    defer z.end();
    z.text(error_message);

    log.debug(comptime "printing error for " ++ command.name, .{});

    output: {
        io.stderr.writeAll(exe_path) catch break :output;
        io.stderr.writeAll(": ") catch break :output;
        io.stderr.writeAll(error_message) catch break :output;
        io.stderr.writeAll("\nview '") catch break :output;
        io.stderr.writeAll(exe_path) catch break :output;
        io.stderr.writeAll(" --help' for more information\n") catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printInvalidUsageAlloc(
    comptime command: type,
    allocator: std.mem.Allocator,
    io: IO,
    exe_path: []const u8,
    comptime msg: []const u8,
    args: anytype,
) error{ OutOfMemory, AlreadyHandled } {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print invalid usage alloc" });
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer if (free_on_close) allocator.free(error_message);

    return printInvalidUsage(command, io, exe_path, error_message);
}

pub const IO = struct {
    stderr: std.io.AnyWriter,
    stdin: std.io.AnyReader,
    stdout: std.io.AnyWriter,
};

pub fn mapFile(
    comptime command: type,
    allocator: std.mem.Allocator,
    io: IO,
    cwd: std.fs.Dir,
    path: []const u8,
) error{ AlreadyHandled, OutOfMemory }!MappedFile {
    const file = cwd.openFile(path, .{}) catch
        return printErrorAlloc(
            command,
            allocator,
            io,
            "unable to open '{s}'",
            .{path},
        );
    errdefer if (free_on_close) file.close();

    const stat = file.stat() catch |err|
        return printErrorAlloc(
            command,
            allocator,
            io,
            "unable to stat '{s}': {s}",
            .{ path, @errorName(err) },
        );

    if (stat.size == 0) {
        @branchHint(.unlikely);
        return .{
            .file = file,
            .file_contents = &.{},
        };
    }

    const file_contents = std.posix.mmap(
        null,
        stat.size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    ) catch |err|
        return printErrorAlloc(
            command,
            allocator,
            io,
            "unable to map '{s}': {s}",
            .{ path, @errorName(err) },
        );

    return .{
        .file = file,
        .file_contents = file_contents,
    };
}

pub const MappedFile = struct {
    file: std.fs.File,
    file_contents: []align(std.heap.page_size_min) const u8,

    pub fn close(self: MappedFile) void {
        if (free_on_close) {
            if (self.file_contents.len != 0) {
                @branchHint(.likely);
                std.posix.munmap(self.file_contents);
            }
            self.file.close();
        }
    }
};

pub fn readFileIntoBuffer(
    comptime command: type,
    allocator: std.mem.Allocator,
    io: IO,
    cwd: std.fs.Dir,
    path: []const u8,
    buffer: []u8,
) error{ AlreadyHandled, OutOfMemory }![]const u8 {
    const file = cwd.openFile(path, .{}) catch
        return printErrorAlloc(
            command,
            allocator,
            io,
            "unable to open '{s}'",
            .{path},
        );
    defer if (free_on_close) file.close();

    const reader = file.reader();
    const read = reader.readAll(buffer) catch |err|
        return printErrorAlloc(
            command,
            allocator,
            io,
            "unable to read file '{s}': {s}",
            .{ path, @errorName(err) },
        );

    return buffer[0..read];
}

pub const ArgIterator = union(enum) {
    args: std.process.ArgIterator,
    slice: struct {
        slice: []const [:0]const u8,
        index: usize = 0,
    },

    pub fn nextRaw(self: *ArgIterator) ?[:0]const u8 {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "raw next arg" });
        defer z.end();

        if (self.dispatchNext()) |arg| {
            @branchHint(.likely);
            z.text(arg);
            return arg;
        }

        return null;
    }

    pub fn next(self: *ArgIterator) ?Arg {
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
        self: *ArgIterator,
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

    inline fn dispatchNext(self: *ArgIterator) ?[:0]const u8 {
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
        comptime command: type,
        io: IO,
    ) error{AlreadyHandled}!?Entry {
        if (self.index >= self.passwd_file_contents.len) {
            @branchHint(.unlikely);
            return null;
        }

        const remaining = self.passwd_file_contents[self.index..];

        const line_length =
            std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len - 1;

        self.index += line_length + 1;

        var column_iter = std.mem.tokenizeScalar(
            u8,
            remaining[0..line_length],
            ':',
        );

        const user_name = column_iter.next() orelse
            return printError(command, io, "format of '/etc/passwd' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return printError(command, io, "format of '/etc/passwd' is invalid");

        const user_id_slice = column_iter.next() orelse
            return printError(command, io, "format of '/etc/passwd' is invalid");

        const primary_group_id_slice = column_iter.next() orelse
            return printError(command, io, "format of '/etc/passwd' is invalid");

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

        pub fn iterateMembers(self: *const Entry) std.mem.TokenIterator(u8, .scalar) {
            return std.mem.tokenizeScalar(u8, self.members_slice orelse &[_]u8{}, ',');
        }
    };

    /// The returned `Entry` is invalidated on any subsequent call to `next`
    pub fn next(
        self: *GroupFileIterator,
        comptime command: type,
        io: IO,
    ) error{AlreadyHandled}!?Entry {
        if (self.index >= self.group_file_contents.len) {
            @branchHint(.unlikely);
            return null;
        }

        const remaining = self.group_file_contents[self.index..];

        const line_length =
            std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len - 1;

        self.index += line_length + 1;

        var column_iter = std.mem.tokenizeScalar(
            u8,
            remaining[0..line_length],
            ':',
        );

        const group_name = column_iter.next() orelse
            return printError(command, io, "format of '/etc/group' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return printError(command, io, "format of '/etc/group' is invalid");

        const group_id_slice = column_iter.next() orelse
            return printError(command, io, "format of '/etc/group' is invalid");

        return .{
            .group_name = group_name,
            .group_id = group_id_slice,
            .members_slice = column_iter.next(),
        };
    }
};

pub const MaybeAllocatedString = MaybeAllocated(
    []const u8,
    struct {
        fn freeSlice(self: []const u8, allocator: std.mem.Allocator) void {
            allocator.free(self);
        }
    }.freeSlice,
);

pub fn MaybeAllocated(comptime T: type, comptime dealloc: fn (self: T, allocator: std.mem.Allocator) void) type {
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

pub const CommandExposedError = error{
    OutOfMemory,
    UnableToParseArguments,
    AlreadyHandled,
};

const CommandNonError = error{
    ShortHelp,
    FullHelp,
    Version,
};

pub const CommandError = CommandExposedError || CommandNonError;

pub fn narrowCommandError(
    comptime command: type,
    io: IO,
    exe_path: []const u8,
    err: CommandError,
) CommandExposedError!void {
    return switch (err) {
        error.ShortHelp => printShortHelp(command, io, exe_path),
        error.FullHelp => printFullHelp(command, io, exe_path),
        error.Version => printVersion(command, io),
        else => |narrow_err| narrow_err,
    };
}

pub fn testExecute(
    comptime command: type,
    arguments: []const [:0]const u8,
    settings: anytype,
) CommandExposedError!void {
    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else VoidWriter.writer();

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

    var arg_iter: ArgIterator = .{ .slice = .{ .slice = arguments } };

    const io: IO = .{
        .stderr = stderr.any(),
        .stdin = stdin.any(),
        .stdout = stdout.any(),
    };

    return command.execute(
        std.testing.allocator,
        io,
        &arg_iter,
        cwd,
        command.name,
    ) catch |full_err| narrowCommandError(command, io, command.name, full_err);
}

pub fn testError(
    comptime command: type,
    arguments: []const [:0]const u8,
    settings: anytype,
    expected_error: []const u8,
) !void {
    const SettingsType = @TypeOf(settings);
    if (@hasField(SettingsType, "stderr")) @compileError("there is already a stderr defined on this settings type");
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

    var stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr.deinit();

    try std.testing.expectError(error.AlreadyHandled, testExecute(
        command,
        arguments,
        .{
            .stderr = stderr.writer(),
            .stdin = stdin,
            .stdout = stdout,
            .cwd = cwd,
        },
    ));

    std.testing.expect(std.mem.indexOf(u8, stderr.items, expected_error) != null) catch |err| {
        std.debug.print("\nEXPECTED: {s}\n\nACTUAL: {s}\n", .{ expected_error, stderr.items });
        return err;
    };
}

pub fn testHelp(comptime command: type, comptime include_shorthand: bool) !void {
    const full_help = try std.fmt.allocPrint(
        std.testing.allocator,
        if (@hasDecl(command, "extended_help"))
            comptime command.short_help ++ "\n" ++ command.extended_help
        else
            command.short_help,
        .{command.name},
    );

    defer std.testing.allocator.free(full_help);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try testExecute(
        command,
        &.{"--help"},
        .{ .stdout = out.writer() },
    );

    try std.testing.expectEqualStrings(full_help, out.items);

    if (include_shorthand) {
        const short_expected_help = try std.fmt.allocPrint(
            std.testing.allocator,
            command.short_help,
            .{command.name},
        );
        defer std.testing.allocator.free(short_expected_help);

        out.clearRetainingCapacity();

        try testExecute(
            command,
            &.{"-h"},
            .{ .stdout = out.writer() },
        );

        try std.testing.expectEqualStrings(short_expected_help, out.items);
    }
}

pub fn testVersion(comptime command: type) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try testExecute(
        command,
        &.{"--version"},
        .{
            .stdout = out.writer(),
        },
    );

    const expected = try std.fmt.allocPrint(
        std.testing.allocator,
        version_string,
        .{command.name},
    );
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, out.items);
}

const SliceArgIterator = struct {
    slice: []const [:0]const u8,
    index: usize = 0,

    pub fn next(self: *SliceArgIterator) ?[:0]const u8 {
        if (self.index < self.slice.len) {
            defer self.index += 1;
            return self.slice[self.index];
        }
        return null;
    }
};

const VoidReader = struct {
    pub const Reader = std.io.Reader(void, error{}, read);
    pub fn reader() Reader {
        return .{ .context = {} };
    }

    fn read(_: void, buffer: []u8) error{}!usize {
        _ = buffer;
        return 0;
    }
};

const VoidWriter = struct {
    pub const Writer = std.io.Writer(void, error{}, write);
    pub fn writer() Writer {
        return .{ .context = {} };
    }

    fn write(_: void, bytes: []const u8) error{}!usize {
        return bytes.len;
    }
};

const builtin = @import("builtin");
const log = std.log.scoped(.shared);
const options = @import("options");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
