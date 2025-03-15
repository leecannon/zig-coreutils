// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub fn main() if (shared.is_debug_or_test) shared.CommandExposedError!u8 else u8 {
    // this causes the frame to start with our main instead of `std.start`
    tracy.frameMark(null);
    const main_z: tracy.Zone = .begin(.{ .src = @src(), .name = "main" });
    defer main_z.end();

    const static = struct {
        var debug_allocator: if (shared.is_debug_or_test) std.heap.DebugAllocator(.{}) else void =
            if (shared.is_debug_or_test) .init else {};
        var tracy_allocator: if (options.trace) tracy.Allocator else void =
            if (options.trace) undefined else {};
    };
    defer {
        if (shared.is_debug_or_test) _ = static.debug_allocator.deinit();
    }

    const allocator = blk: {
        const gpa_allocator = if (shared.is_debug_or_test)
            static.debug_allocator.allocator()
        else
            std.heap.smp_allocator;

        if (options.trace) {
            static.tracy_allocator = .{ .parent = gpa_allocator };
            break :blk static.tracy_allocator.allocator();
        } else {
            break :blk gpa_allocator;
        }
    };

    var arg_iter = std.process.args();

    const exe_path = arg_iter.next() orelse unreachable;
    const basename = std.fs.path.basename(exe_path);
    log.debug("got exe_path: \"{s}\" with basename: \"{s}\"", .{ exe_path, basename });

    var std_in_buffered = std.io.bufferedReader(std.io.getStdIn().reader());
    var std_out_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());

    const stderr_writer = std.io.getStdErr().writer();
    const io: shared.IO = .{
        .stderr = stderr_writer.any(),
        .stdin = std_in_buffered.reader().any(),
        .stdout = std_out_buffered.writer().any(),
    };

    tryExecute(
        allocator,
        arg_iter,
        io,
        basename,
        std.fs.cwd(),
        exe_path,
    ) catch |err| {
        switch (err) {
            error.OutOfMemory => stderr_writer.writeAll("out of memory\n") catch {},
            error.UnableToParseArguments => stderr_writer.writeAll("unable to parse arguments\n") catch {},
            error.AlreadyHandled => return 1, // TODO: should this error be return as well?
        }

        if (shared.is_debug_or_test) return err;
        return 1;
    };

    std_out_buffered.flush() catch |err| {
        shared.unableToWriteTo("stdout", io, err) catch {};
        return 1;
    };

    return 0;
}

pub fn tryExecute(
    allocator: std.mem.Allocator,
    os_arg_iter: std.process.ArgIterator,
    io: shared.IO,
    basename: []const u8,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) shared.CommandExposedError!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "tryExecute" });
    defer z.end();

    var arg_iter: shared.ArgIterator = .{ .args = os_arg_iter };

    if (!std.mem.eql(u8, basename, "zig-coreutils")) {
        inline for (COMMANDS) |command| {
            if (std.mem.eql(u8, command.name, basename)) {
                z.text(basename);
                return command.execute(
                    allocator,
                    io,
                    &arg_iter,
                    cwd,
                    exe_path,
                ) catch |full_err|
                    shared.narrowCommandError(command, io, basename, full_err);
            }
        }

        io.stderr.print(
            \\{0s}: command '{1s}' not found
            \\the name of this executable/symlink is not a valid command
            \\view available commands with 'zig-coreutils --list'
            \\
        , .{ exe_path, basename }) catch {};
        return error.AlreadyHandled;
    }

    const opt_possible_command_arg = arg_iter.nextWithHelpOrVersion(true) catch |err| switch (err) {
        error.Version => {
            io.stdout.writeAll(shared.base_version_string) catch |inner_err|
                return shared.unableToWriteTo("stdout", io, inner_err);
            return;
        },
        error.ShortHelp => {
            io.stdout.print(short_help, .{exe_path}) catch |inner_err|
                return shared.unableToWriteTo("stdout", io, inner_err);
            return;
        },
        error.FullHelp => {
            io.stdout.print(full_help, .{exe_path}) catch |inner_err|
                return shared.unableToWriteTo("stdout", io, inner_err);
            return;
        },
    };

    if (opt_possible_command_arg) |possible_command_arg| {
        switch (possible_command_arg.arg_type) {
            .longhand => |longhand| {
                if (std.mem.eql(u8, longhand, "list")) {
                    io.stdout.writeAll(command_list) catch |inner_err|
                        return shared.unableToWriteTo("stdout", io, inner_err);
                    return;
                }
            },
            else => {},
        }

        const possible_command = possible_command_arg.raw;

        log.debug("no command found matching basename '{s}', trying first argument '{s}'", .{
            basename,
            possible_command,
        });

        inline for (COMMANDS) |command| {
            if (std.mem.eql(u8, command.name, possible_command)) {
                z.text(possible_command);

                const exe_path_with_command = try std.fmt.allocPrint(allocator, "{s} {s}", .{
                    exe_path,
                    command.name,
                });
                defer if (shared.free_on_close) allocator.free(exe_path_with_command);

                return command.execute(
                    allocator,
                    io,
                    &arg_iter,
                    cwd,
                    exe_path_with_command,
                ) catch |full_err|
                    shared.narrowCommandError(command, io, exe_path_with_command, full_err);
            }
        }

        io.stderr.print(
            \\{0s}: command '{1s}' not found
            \\view available commands with '{0s} --list'
            \\
        , .{ exe_path, possible_command }) catch {};
        return error.AlreadyHandled;
    } else {
        io.stderr.print(
            \\{0s}: no command or option specified
            \\view '{0s} --help' for more information
            \\
        , .{exe_path}) catch {};

        return error.AlreadyHandled;
    }

    comptime unreachable;
}

const COMMANDS = [_]type{
    @import("commands/basename.zig"),
    @import("commands/clear.zig"),
    @import("commands/dirname.zig"),
    @import("commands/false.zig"),
    @import("commands/groups.zig"),
    @import("commands/nproc.zig"),
    @import("commands/touch.zig"),
    @import("commands/true.zig"),
    @import("commands/whoami.zig"),
    @import("commands/yes.zig"),
};

const short_help =
    \\Usage: {0s} command [arguments]...
    \\   or: command [arguments]...
    \\   or: {0s} OPTION
    \\
    \\A multi-call binary combining many common utilities into a single executable.
    \\
    \\A command can be specified using the first argument or by creating a symlink with the name of the command.
    \\
    \\  --list     list all available commands
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

const commands_per_line = 5;

const full_help = blk: {
    var help: []const u8 = short_help ++
        \\
        \\Available commands:
        \\
    ;

    for (COMMANDS, 0..) |command, i| {
        const n = i % commands_per_line;

        if (n == 0) help = help ++ "  ";
        help = help ++ command.name;

        if (i == COMMANDS.len - 1) {
            help = help ++ "\n";
            break;
        }

        if (n == commands_per_line - 1) {
            help = help ++ ",\n";
        } else {
            help = help ++ ", ";
        }
    }

    break :blk help;
};

const command_list = blk: {
    var list: []const u8 = "";

    for (COMMANDS) |command| {
        list = list ++ command.name ++ "\n";
    }

    break :blk list;
};

const builtin = @import("builtin");
const log = std.log.scoped(.main);
const options = @import("options");
const shared = @import("shared.zig");
const std = @import("std");
const tracy = @import("tracy");

pub const tracy_impl = @import("tracy_impl");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
