// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const Command = @This();

name: [:0]const u8,

/// The short help text for the command.
///
/// This is used for the `-h` short help option.
///
/// No formatting is performed on this except for the replacement of `{NAME}` with the exepath.
short_help: []const u8,

/// The extended help text for the command, usually containing examples.
///
/// This is appended to the short help text and used for the `--help` long help option.
///
/// No text replacement is performed on this.
extended_help: ?[]const u8 = null,

execute: *const fn (
    allocator: std.mem.Allocator,
    io: IO,
    args: *Arg.Iterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) Error!void,

pub const Error = ExposedError || NonError;

pub const ExposedError = error{
    OutOfMemory,
    AlreadyHandled,
};

const NonError = error{
    ShortHelp,
    FullHelp,
    Version,
};

pub fn narrowError(
    command: Command,
    io: IO,
    exe_path: []const u8,
    err: Error,
) ExposedError!void {
    return switch (err) {
        error.ShortHelp => command.printShortHelp(io, exe_path),
        error.FullHelp => command.printFullHelp(io, exe_path),
        error.Version => command.printVersion(io),
        else => |narrow_err| narrow_err,
    };
}

fn printShortHelp(command: Command, io: IO, exe_path: []const u8) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print short help" });
    defer z.end();

    std.debug.assert(command.short_help.len != 0); // short help should not be empty
    std.debug.assert(command.short_help[command.short_help.len - 1] == '\n'); // short help should end with a newline

    var iter: NameReplacementIterator = .{ .slice = command.short_help };

    while (iter.next()) |result| {
        try io.stdoutWriteAll(result.slice);
        if (result.output_name) try io.stdoutWriteAll(exe_path);
    }
}

fn printFullHelp(command: Command, io: IO, exe_path: []const u8) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print full help" });
    defer z.end();

    std.debug.assert(command.short_help.len != 0); // short help should not be empty
    std.debug.assert(command.short_help[command.short_help.len - 1] == '\n'); // short help should end with a newline

    var iter: NameReplacementIterator = .{ .slice = command.short_help };

    while (iter.next()) |result| {
        try io.stdoutWriteAll(result.slice);
        if (result.output_name) try io.stdoutWriteAll(exe_path);
    }

    if (command.extended_help) |extended_help| {
        std.debug.assert(extended_help.len != 0); // non-null extended help should not be empty
        std.debug.assert(extended_help[extended_help.len - 1] == '\n'); // extended help should end with a newline

        try io.stdoutWriteByte('\n');
        try io.stdoutWriteAll(extended_help);
    }
}

fn printVersion(command: Command, io: IO) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print version" });
    defer z.end();

    var iter: NameReplacementIterator = .{ .slice = shared.version_string };

    while (iter.next()) |result| {
        try io.stdoutWriteAll(result.slice);
        if (result.output_name) try io.stdoutWriteAll(command.name);
    }
}

pub fn printError(command: Command, io: IO, error_message: []const u8) error{AlreadyHandled} {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print error" });
    defer z.end();
    z.text(error_message);

    output: {
        io._stderr.writeAll(command.name) catch break :output;
        io._stderr.writeAll(": ") catch break :output;
        io._stderr.writeAll(error_message) catch break :output;
        io._stderr.writeByte('\n') catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printErrorAlloc(
    command: Command,
    allocator: std.mem.Allocator,
    io: IO,
    comptime msg: []const u8,
    args: anytype,
) error{ OutOfMemory, AlreadyHandled } {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print error alloc" });
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer if (shared.free_on_close) allocator.free(error_message);

    return command.printError(io, error_message);
}

pub fn printInvalidUsage(
    _: Command,
    io: IO,
    exe_path: []const u8,
    error_message: []const u8,
) error{AlreadyHandled} {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print invalid usage" });
    defer z.end();
    z.text(error_message);

    output: {
        io._stderr.writeAll(exe_path) catch break :output;
        io._stderr.writeAll(": ") catch break :output;
        io._stderr.writeAll(error_message) catch break :output;
        io._stderr.writeAll("\nview '") catch break :output;
        io._stderr.writeAll(exe_path) catch break :output;
        io._stderr.writeAll(" --help' for more information\n") catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printInvalidUsageAlloc(
    command: Command,
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
    defer if (shared.free_on_close) allocator.free(error_message);

    return command.printInvalidUsage(io, exe_path, error_message);
}

pub fn testExecute(
    command: Command,
    arguments: []const []const u8,
    settings: anytype,
) ExposedError!void {
    std.debug.assert(builtin.is_test);

    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin"))
        settings.stdin
    else
        VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout"))
        settings.stdout
    else
        VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr"))
        settings.stderr
    else
        VoidWriter.writer();

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

    var arg_iter: Arg.Iterator = .{ .slice = .{ .slice = arguments } };

    const io: IO = .{
        ._stderr = stderr.any(),
        ._stdin = stdin.any(),
        ._stdout = stdout.any(),
    };

    return command.execute(
        std.testing.allocator,
        io,
        &arg_iter,
        cwd,
        command.name,
    ) catch |full_err| command.narrowError(io, command.name, full_err);
}

pub fn testError(
    command: Command,
    arguments: []const []const u8,
    settings: anytype,
    expected_error: []const u8,
) !void {
    std.debug.assert(builtin.is_test);

    const SettingsType = @TypeOf(settings);

    if (@hasField(SettingsType, "stderr")) {
        @compileError("`testError` does not support `stderr` on the settings type");
    }

    const stdin = if (@hasField(SettingsType, "stdin"))
        settings.stdin
    else
        VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout"))
        settings.stdout
    else
        VoidWriter.writer();

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

    var stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr.deinit();

    try std.testing.expectError(error.AlreadyHandled, command.testExecute(
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

pub fn testHelp(command: Command, comptime include_shorthand: bool) !void {
    std.debug.assert(builtin.is_test);

    const full_expected_help = blk: {
        var sb: std.ArrayListUnmanaged(u8) = .empty;
        errdefer sb.deinit(std.testing.allocator);

        var iter: NameReplacementIterator = .{ .slice = command.short_help };
        while (iter.next()) |result| {
            try sb.appendSlice(std.testing.allocator, result.slice);
            if (result.output_name) {
                try sb.appendSlice(std.testing.allocator, command.name);
            }
        }

        if (command.extended_help) |extended_help| {
            try sb.append(std.testing.allocator, '\n');
            try sb.appendSlice(std.testing.allocator, extended_help);
        }

        break :blk try sb.toOwnedSlice(std.testing.allocator);
    };
    defer std.testing.allocator.free(full_expected_help);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try command.testExecute(
        &.{"--help"},
        .{ .stdout = out.writer() },
    );

    try std.testing.expectEqualStrings(full_expected_help, out.items);

    if (include_shorthand) {
        const short_expected_help = blk: {
            var sb: std.ArrayListUnmanaged(u8) = .empty;
            errdefer sb.deinit(std.testing.allocator);

            var iter: NameReplacementIterator = .{ .slice = command.short_help };
            while (iter.next()) |result| {
                try sb.appendSlice(std.testing.allocator, result.slice);
                if (result.output_name) {
                    try sb.appendSlice(std.testing.allocator, command.name);
                }
            }

            break :blk try sb.toOwnedSlice(std.testing.allocator);
        };
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

pub fn testVersion(command: Command) !void {
    std.debug.assert(builtin.is_test);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try command.testExecute(
        &.{"--version"},
        .{
            .stdout = out.writer(),
        },
    );

    const expected = blk: {
        var sb: std.ArrayListUnmanaged(u8) = .empty;
        errdefer sb.deinit(std.testing.allocator);

        var iter: NameReplacementIterator = .{ .slice = shared.version_string };
        while (iter.next()) |result| {
            try sb.appendSlice(std.testing.allocator, result.slice);
            if (result.output_name) {
                try sb.appendSlice(std.testing.allocator, command.name);
            }
        }

        break :blk try sb.toOwnedSlice(std.testing.allocator);
    };

    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, out.items);
}

pub const TestFuzzOptions = struct {
    /// If true the command is expected to output something to stdout on success.
    expect_stdout_output_on_success: bool = true,

    /// If true the command is expected to output something to stderr on failure.
    expect_stderr_output_on_failure: bool = true,
};

pub fn testFuzz(command: Command, options: TestFuzzOptions) !void {
    std.debug.assert(builtin.is_test);

    const Context = struct {
        inner_command: Command,
        options: TestFuzzOptions,

        fn testOne(context: @This(), input: []const u8) anyerror!void {
            const arguments = blk: {
                var arguments: std.ArrayList([]const u8) = .init(std.testing.allocator);
                errdefer arguments.deinit();

                var iter = std.mem.splitScalar(u8, input, ' ');

                while (iter.next()) |arg| {
                    try arguments.append(arg);
                }

                break :blk try arguments.toOwnedSlice();
            };
            defer std.testing.allocator.free(arguments);

            var stdout: std.ArrayList(u8) = .init(std.testing.allocator);
            defer stdout.deinit();

            var stderr: std.ArrayList(u8) = .init(std.testing.allocator);
            defer stderr.deinit();

            context.inner_command.testExecute(
                arguments,
                .{ .stdout = stdout.writer(), .stderr = stderr.writer() },
            ) catch |err| {
                switch (err) {
                    error.OutOfMemory => {
                        // this error is output by main and some output may or not have been written to stderr
                    },
                    error.AlreadyHandled => if (context.options.expect_stderr_output_on_failure) {
                        try std.testing.expect(stderr.items.len != 0);
                    },
                }
                return;
            };

            try std.testing.expect(stderr.items.len == 0);
            if (context.options.expect_stdout_output_on_success) {
                try std.testing.expect(stdout.items.len != 0);
            }
        }
    };
    try std.testing.fuzz(
        Context{
            .inner_command = command,
            .options = options,
        },
        Context.testOne,
        .{},
    );
}

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

const NameReplacementIterator = struct {
    slice: []const u8,

    const Result = struct {
        slice: []const u8,
        output_name: bool,
    };

    const NAME_STAND_IN = "{NAME}";

    pub fn next(self: *NameReplacementIterator) ?Result {
        if (self.slice.len == 0) return null;

        const index_of_name = std.mem.indexOf(u8, self.slice, NAME_STAND_IN) orelse {
            defer self.slice = &.{};
            return .{ .slice = self.slice, .output_name = false };
        };

        const output_slice = self.slice[0..index_of_name];
        self.slice = self.slice[index_of_name + NAME_STAND_IN.len ..];

        return .{ .slice = output_slice, .output_name = true };
    }
};

const Arg = @import("Arg.zig");
const IO = @import("IO.zig");
const shared = @import("shared.zig");

const builtin = @import("builtin");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
