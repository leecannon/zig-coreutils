const std = @import("std");
const args = @import("args");

const log = std.log.scoped(.subcommand);

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/false.zig"),
    @import("subcommands/true.zig"),
};

pub const ExecuteError = error{
    NoSubcommand,
    FailedToParseArguments,
} || Error;

pub const Error = error{
    OutOfMemory,
};

pub fn executeSubcommand(
    allocator: *std.mem.Allocator,
    arg_iter: anytype,
    io: anytype,
    basename: []const u8,
    exe_path: []const u8,
) ExecuteError!u8 {
    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) return try execute(
            subcommand,
            allocator,
            arg_iter,
            io,
            exe_path,
        );
    }

    return error.NoSubcommand;
}

fn execute(
    comptime subcommand: type,
    allocator: *std.mem.Allocator,
    arg_iter: anytype,
    io: anytype,
    exe_path: []const u8,
) !u8 {
    var errors = args.ErrorCollection.init(allocator);
    defer errors.deinit();
    return internalExecute(
        subcommand,
        allocator,
        arg_iter,
        io,
        exe_path,
        .{ .collect = &errors },
    ) catch |err| switch (err) {
        error.InvalidArguments => {
            // TODO: print error and usage
            // std.log.info("{any}", .{errors.errors()});
            return 1;
        },
        else => |narrow_err| return narrow_err,
    };
}

pub fn testExecute(comptime subcommand: type, arguments: []const []const u8, comptime settings: anytype) ExecuteError!u8 {
    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else VoidWriter.writer();

    var arg_iter = SliceArgIterator{ .slice = arguments };

    return internalExecute(
        subcommand,
        std.testing.allocator,
        &arg_iter,
        .{
            .stderr = stderr,
            .stdin = stdin,
            .stdout = stdout,
        },
        subcommand.name,
        .silent,
    ) catch |err| switch (err) {
        error.InvalidArguments => unreachable, // this error type is only returned when using collect error handling
        else => |narrow_err| return narrow_err,
    };
}

fn internalExecute(
    comptime subcommand: type,
    allocator: *std.mem.Allocator,
    arg_iter: anytype,
    io: anytype,
    exe_path: []const u8,
    error_handling: args.ErrorHandling,
) !u8 {
    const options = args.parse(subcommand.OptionsDefinition, arg_iter, allocator, error_handling) catch |err| {
        if (err == error.InvalidArguments and error_handling == .collect) {
            // In the case of collect error handling, pass `error.InvalidArguments` up to notify the caller
            // that there were errors collected
            return error.InvalidArguments;
        }

        return error.FailedToParseArguments;
    };
    defer options.deinit();

    return try subcommand.execute(allocator, io, exe_path, options.options, options.positionals);
}

const SliceArgIterator = struct {
    slice: []const []const u8,
    index: usize = 0,

    pub fn next(self: *SliceArgIterator, allocator: *std.mem.Allocator) ?(std.process.ArgIterator.NextError![:0]u8) {
        if (self.index < self.slice.len) {
            const ret = allocator.dupeZ(u8, self.slice[self.index]);
            self.index += 1;
            return ret;
        }
        return null;
    }

    pub fn skip(self: *SliceArgIterator) bool {
        if (self.index < self.slice.len) {
            self.index += 1;
            return true;
        }
        return false;
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
