const std = @import("std");
const args = @import("args");

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/false.zig"),
    @import("subcommands/true.zig"),
};

pub const ExecuteError = error{
    NoSubcommand,
    FailedToParseArguments,
    HelpOrVersion,
} || Error;

pub const Error = error{
    OutOfMemory,
};

pub fn executeSubcommand(context: anytype) ExecuteError!u8 {
    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, context.basename)) return try execute(subcommand, context);
    }

    return error.NoSubcommand;
}

fn execute(comptime subcommand: type, context: anytype) !u8 {
    var errors = args.ErrorCollection.init(context.allocator);
    defer errors.deinit();
    return internalExecute(
        subcommand,
        context.arg_iter,
        context.exe_path,
        .{
            .allocator = context.allocator,
            .std_err = context.std_err,
            .std_in = context.std_in,
            .std_out = context.std_out,
        },
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
    const std_in = if (@hasField(SettingsType, "std_in")) settings.std_in else VoidReader.reader();
    const std_out = if (@hasField(SettingsType, "std_out")) settings.std_out else VoidWriter.writer();
    const std_err = if (@hasField(SettingsType, "std_err")) settings.std_err else VoidWriter.writer();

    var arg_iter = SliceArgIterator{ .slice = arguments };

    return internalExecute(
        subcommand,
        &arg_iter,
        subcommand.name,
        .{
            .allocator = std.testing.allocator,
            .std_err = std_err,
            .std_in = std_in,
            .std_out = std_out,
        },
        .silent,
    ) catch |err| switch (err) {
        error.InvalidArguments => unreachable, // this error type is only returned when using collect error handling
        else => |narrow_err| return narrow_err,
    };
}

fn internalExecute(
    comptime subcommand: type,
    arg_iter: anytype,
    exe_path: []const u8,
    context: anytype,
    error_handling: args.ErrorHandling,
) !u8 {
    const options = args.parse(subcommand.options_def, arg_iter, context.allocator, error_handling) catch |err| {
        if (err == error.InvalidArguments and error_handling == .collect) {
            // In the case of collect error handling, pass `error.InvalidArguments` up to notify the caller
            // that there were errors collected
            return error.InvalidArguments;
        }

        return error.FailedToParseArguments;
    };
    defer options.deinit();

    if (options.options.help) {
        context.std_out.print(subcommand.usage, .{exe_path}) catch {};
        return error.HelpOrVersion;
    }
    if (options.options.version) {
        context.std_out.print(
            \\{s} (zig-coreutils) 0.0.1
            \\MIT License Copyright (c) 2021 Lee Cannon
            \\
        , .{subcommand.name}) catch {};
        return error.HelpOrVersion;
    }

    return try subcommand.execute(context, options);
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
