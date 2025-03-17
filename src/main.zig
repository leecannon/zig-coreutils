// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const commands = &.{
    .{ "basename", @import("commands/basename.zig").command },
    .{ "clear", @import("commands/clear.zig").command },
    .{ "dirname", @import("commands/dirname.zig").command },
    .{ "false", @import("commands/false.zig").command },
    .{ "groups", @import("commands/groups.zig").command },
    .{ "nproc", @import("commands/nproc.zig").command },
    .{ "touch", @import("commands/touch.zig").command },
    .{ "true", @import("commands/true.zig").command },
    .{ "whoami", @import("commands/whoami.zig").command },
    .{ "yes", @import("commands/yes.zig").command },
};

pub fn main() if (shared.is_debug_or_test) Command.ExposedError!u8 else u8 {
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
    const io: IO = .{
        ._stderr = stderr_writer.any(),
        ._stdin = std_in_buffered.reader().any(),
        ._stdout = std_out_buffered.writer().any(),
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
            error.AlreadyHandled => return 1, // TODO: should this error be returned as well?
        }

        if (shared.is_debug_or_test) return err;
        return 1;
    };

    std_out_buffered.flush() catch |err| {
        io.unableToWriteTo("stdout", err) catch {};
        return 1;
    };

    return 0;
}

fn tryExecute(
    allocator: std.mem.Allocator,
    os_arg_iter: std.process.ArgIterator,
    io: IO,
    basename: []const u8,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) Command.ExposedError!void {
    const z: tracy.Zone = .begin(.{ .src = @src(), .name = "tryExecute" });
    defer z.end();

    var arg_iter: Arg.Iterator = .{ .args = os_arg_iter };

    // attempt to match the basename to a command
    if (command_lookup.get(basename)) |command| {
        z.text(basename);
        return command.execute(
            allocator,
            io,
            &arg_iter,
            cwd,
            exe_path,
        ) catch |full_err| command.narrowError(io, basename, full_err);
    }

    // check the first argument for an option
    const opt_possible_command_arg = arg_iter.nextWithHelpOrVersion(true) catch |err| switch (err) {
        error.Version => {
            try io.stdoutWriteAll(shared.base_version_string);
            return;
        },
        error.ShortHelp => {
            try io.stdoutPrint(short_help, .{exe_path});
            return;
        },
        error.FullHelp => {
            try io.stdoutPrint(full_help, .{exe_path});
            return;
        },
    };

    const possible_command_arg = opt_possible_command_arg orelse {
        io._stderr.print(
            \\{0s}: command '{1s}' not found
            \\the name of this executable/symlink is not a valid command and no command specified as first argument
            \\view available commands with 'zig-coreutils --list'
            \\
        , .{ exe_path, basename }) catch {};
        return error.AlreadyHandled;
    };

    // check first argument for `--list` option
    switch (possible_command_arg.arg_type) {
        .longhand => |longhand| {
            if (std.mem.eql(u8, longhand, "list")) {
                try io.stdoutWriteAll(command_list);
                return;
            }
        },
        else => {},
    }

    // attempt to match the first argument to a command
    const possible_command = possible_command_arg.raw;
    const command = command_lookup.get(possible_command) orelse {
        io._stderr.print(
            \\{0s}: command '{1s}' not found
            \\view available commands with '{0s} --list'
            \\
        , .{ exe_path, possible_command }) catch {};
        return error.AlreadyHandled;
    };

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
    ) catch |full_err| command.narrowError(io, exe_path_with_command, full_err);
}

const command_lookup: std.StaticStringMap(Command) = .initComptime(commands);

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

    const number_of_commands = commands.len;

    for (commands, 0..) |command, i| {
        const n = i % commands_per_line;

        if (n == 0) help = help ++ "  ";
        help = help ++ command.@"0";

        if (i == number_of_commands - 1) {
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

    for (commands) |command| {
        list = list ++ command.@"0" ++ "\n";
    }

    break :blk list;
};

const Arg = @import("Arg.zig");
const Command = @import("Command.zig");
const IO = @import("IO.zig");
const shared = @import("shared.zig");

const log = std.log.scoped(.main);

const builtin = @import("builtin");
const options = @import("options");
const std = @import("std");
const tracy = @import("tracy");

pub const tracy_impl = @import("tracy_impl");

comptime {
    if (builtin.is_test) _ = @import("commands/template.zig"); // ensure the template compiles
    std.testing.refAllDeclsRecursive(@This());
}
