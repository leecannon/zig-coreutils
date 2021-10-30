const std = @import("std");
const shared = @import("shared.zig");

const log = std.log.scoped(.subcommand);

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/false.zig"),
    @import("subcommands/true.zig"),
};

pub const ExecuteError = error{
    NoSubcommand,
} || Error;

pub const Error = error{
    OutOfMemory,
};

pub fn executeSubcommand(
    allocator: *std.mem.Allocator,
    arguments: []const []const u8,
    io: anytype,
    basename: []const u8,
    exe_path: []const u8,
) ExecuteError!u8 {
    const z = shared.trace.begin(@src());
    defer z.end();

    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) return execute(
            subcommand,
            allocator,
            arguments,
            io,
            exe_path,
        );
    }

    return error.NoSubcommand;
}

fn execute(
    comptime subcommand: type,
    allocator: *std.mem.Allocator,
    arguments: []const []const u8,
    io: anytype,
    exe_path: []const u8,
) Error!u8 {
    const z = shared.trace.begin(@src());
    defer z.end();

    var arg_iterator = shared.ArgIterator.init(arguments);

    var options: subcommand.Options = .{};

    if (subcommand.parseOptions(io, &options, &arg_iterator, exe_path)) |return_code| {
        return return_code;
    }

    return subcommand.execute(allocator, io, &options);
}

pub fn testExecute(comptime subcommand: type, arguments: []const []const u8, settings: anytype) Error!u8 {
    const z = shared.trace.begin(@src());
    defer z.end();

    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else VoidWriter.writer();

    return execute(
        subcommand,
        std.testing.allocator,
        arguments,
        .{
            .stderr = stderr,
            .stdin = stdin,
            .stdout = stdout,
        },
        subcommand.name,
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
        _ = bytes;
        return bytes.len;
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
