const std = @import("std");
const shared = @import("shared.zig");
const builtin = @import("builtin");

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
    UnableToParseArguments,
};

pub fn execute(
    allocator: *std.mem.Allocator,
    arg_iter: *std.process.ArgIterator,
    io: anytype,
    basename: []const u8,
    exe_path: []const u8,
) ExecuteError!u8 {
    const z = shared.trace.beginNamed(@src(), "execute");
    defer z.end();

    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) return executeSubcommand(
            subcommand,
            allocator,
            arg_iter,
            io,
            exe_path,
        );
    }

    return error.NoSubcommand;
}

fn executeSubcommand(
    comptime subcommand: type,
    allocator: *std.mem.Allocator,
    arg_iter: anytype,
    io: anytype,
    exe_path: []const u8,
) Error!u8 {
    const z = shared.trace.beginNamed(@src(), "execute subcommand");
    defer z.end();

    var arg_iterator = shared.ArgIterator(@TypeOf(arg_iter)).init(arg_iter);
    return subcommand.execute(allocator, io, &arg_iterator, exe_path);
}

pub fn testExecute(comptime subcommand: type, arguments: []const [:0]const u8, settings: anytype) Error!u8 {
    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else VoidWriter.writer();

    var arg_iter = SliceArgIterator{ .slice = arguments };

    return executeSubcommand(
        subcommand,
        std.testing.allocator,
        &arg_iter,
        .{
            .stderr = stderr,
            .stdin = stdin,
            .stdout = stdout,
        },
        subcommand.name,
    );
}

const SliceArgIterator = struct {
    slice: []const [:0]const u8,
    index: usize = 0,

    pub inline fn next(self: *SliceArgIterator, allocator: *std.mem.Allocator) ?(std.process.ArgIterator.NextError![:0]const u8) {
        return allocator.dupeZ(u8, self.nextPosix());
    }

    pub fn nextPosix(self: *SliceArgIterator) ?[:0]const u8 {
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
        _ = bytes;
        return bytes.len;
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
