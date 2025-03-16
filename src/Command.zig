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
    io: shared.IO,
    args: *shared.ArgIterator,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) Error!void,

pub fn printShortHelp(command: Command, io: shared.IO, exe_path: []const u8) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print short help" });
    defer z.end();

    log.debug("printing short help for {s}", .{command.name});

    var iter: NameReplacementIterator = .{ .slice = command.short_help };

    while (iter.next()) |result| {
        io.stdout.writeAll(result.slice) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
        if (result.output_name) {
            io.stdout.writeAll(exe_path) catch |err|
                return shared.unableToWriteTo("stdout", io, err);
        }
    }

    if (command.short_help.len != 0 and command.short_help[command.short_help.len - 1] != '\n') {
        io.stdout.writeByte('\n') catch |err|
            return shared.unableToWriteTo("stdout", io, err);
    }
}

pub fn printFullHelp(command: Command, io: shared.IO, exe_path: []const u8) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print full help" });
    defer z.end();

    log.debug("printing full help for {s}", .{command.name});

    var iter: NameReplacementIterator = .{ .slice = command.short_help };

    while (iter.next()) |result| {
        io.stdout.writeAll(result.slice) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
        if (result.output_name) {
            io.stdout.writeAll(exe_path) catch |err|
                return shared.unableToWriteTo("stdout", io, err);
        }
    }

    if (command.short_help.len != 0 and command.short_help[command.short_help.len - 1] != '\n') {
        io.stdout.writeByte('\n') catch |err|
            return shared.unableToWriteTo("stdout", io, err);
    }

    if (command.extended_help) |extended_help| blk: {
        if (extended_help.len == 0) break :blk;

        io.stdout.writeByte('\n') catch |err|
            return shared.unableToWriteTo("stdout", io, err);
        io.stdout.writeAll(extended_help) catch |err|
            return shared.unableToWriteTo("stdout", io, err);

        if (extended_help[extended_help.len - 1] != '\n') {
            io.stdout.writeByte('\n') catch |err|
                return shared.unableToWriteTo("stdout", io, err);
        }
    }
}

pub fn printVersion(command: Command, io: shared.IO) error{AlreadyHandled}!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print version" });
    defer z.end();

    log.debug("printing version for {s}", .{command.name});

    var iter: NameReplacementIterator = .{ .slice = shared.version_string };

    while (iter.next()) |result| {
        io.stdout.writeAll(result.slice) catch |err|
            return shared.unableToWriteTo("stdout", io, err);
        if (result.output_name) {
            io.stdout.writeAll(command.name) catch |err|
                return shared.unableToWriteTo("stdout", io, err);
        }
    }
}

pub fn printError(command: Command, io: shared.IO, error_message: []const u8) error{AlreadyHandled} {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print error" });
    defer z.end();
    z.text(error_message);

    log.debug("printing error for {s}", .{command.name});

    output: {
        io.stderr.writeAll(command.name) catch break :output;
        io.stderr.writeAll(": ") catch break :output;
        io.stderr.writeAll(error_message) catch break :output;
        io.stderr.writeByte('\n') catch break :output;
    }

    return error.AlreadyHandled;
}

pub fn printErrorAlloc(
    command: Command,
    allocator: std.mem.Allocator,
    io: shared.IO,
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
    command: Command,
    io: shared.IO,
    exe_path: []const u8,
    error_message: []const u8,
) error{AlreadyHandled} {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print invalid usage" });
    defer z.end();
    z.text(error_message);

    log.debug("printing error for {s}", .{command.name});

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
    command: Command,
    allocator: std.mem.Allocator,
    io: shared.IO,
    exe_path: []const u8,
    comptime msg: []const u8,
    args: anytype,
) error{ OutOfMemory, AlreadyHandled } {
    @branchHint(.cold);

    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "print invalid usage alloc" });
    defer z.end();

    const error_message = try std.fmt.allocPrint(allocator, msg, args);
    defer if (shared.free_on_close) allocator.free(error_message);

    return printInvalidUsage(command, io, exe_path, error_message);
}

pub const ExposedError = error{
    OutOfMemory,
    UnableToParseArguments,
    AlreadyHandled,
};

const NonError = error{
    ShortHelp,
    FullHelp,
    Version,
};

pub const Error = ExposedError || NonError;

pub fn narrowError(
    command: Command,
    io: shared.IO,
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

pub fn testExecute(
    command: Command,
    arguments: []const [:0]const u8,
    settings: anytype,
) ExposedError!void {
    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else shared.VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else shared.VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else shared.VoidWriter.writer();

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

    var arg_iter: shared.ArgIterator = .{ .slice = .{ .slice = arguments } };

    const io: shared.IO = .{
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
    ) catch |full_err| command.narrowError(io, command.name, full_err);
}

pub fn testError(
    command: Command,
    arguments: []const [:0]const u8,
    settings: anytype,
    expected_error: []const u8,
) !void {
    const SettingsType = @TypeOf(settings);
    if (@hasField(SettingsType, "stderr")) @compileError("there is already a stderr defined on this settings type");
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else shared.VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else shared.VoidWriter.writer();

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

pub fn testHelp(command: Command, comptime include_shorthand: bool) !void {
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

        if (command.short_help.len != 0 and command.short_help[command.short_help.len - 1] != '\n') {
            try sb.append(std.testing.allocator, '\n');
        }

        if (command.extended_help) |extended_help| extended_help: {
            if (extended_help.len == 0) break :extended_help;

            try sb.append(std.testing.allocator, '\n');
            try sb.appendSlice(std.testing.allocator, extended_help);

            if (extended_help[extended_help.len - 1] != '\n') {
                try sb.append(std.testing.allocator, '\n');
            }
        }
        break :blk try sb.toOwnedSlice(std.testing.allocator);
    };
    defer std.testing.allocator.free(full_expected_help);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try testExecute(
        command,
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

            if (command.short_help.len != 0 and command.short_help[command.short_help.len - 1] != '\n') {
                try sb.append(std.testing.allocator, '\n');
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
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try testExecute(
        command,
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

const log = std.log.scoped(.command);
const shared = @import("shared.zig");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
