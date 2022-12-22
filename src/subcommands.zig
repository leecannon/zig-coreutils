const std = @import("std");
const shared = @import("shared.zig");
const zsw = @import("zsw");
const builtin = @import("builtin");

const log = std.log.scoped(.subcommand);

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/basename.zig"),
    @import("subcommands/clear.zig"),
    @import("subcommands/dirname.zig"),
    @import("subcommands/false.zig"),
    @import("subcommands/groups.zig"),
    @import("subcommands/true.zig"),
    @import("subcommands/whoami.zig"),
    @import("subcommands/yes.zig"),
};

pub const ExecuteError = error{
    NoSubcommand,
} || SubcommandErrors;

const SubcommandErrors = error{
    OutOfMemory,
    UnableToParseArguments,
};

const SubcommandNonErrors = error{
    Help,
    Version,
};

pub const Error = SubcommandErrors || SubcommandNonErrors;

pub fn execute(
    allocator: std.mem.Allocator,
    arg_iter: *std.process.ArgIterator,
    io: anytype,
    basename: []const u8,
    system: zsw.System,
    exe_path: []const u8,
) ExecuteError!u8 {
    const z = shared.tracy.traceNamed(@src(), "execute");
    defer z.end();
    z.addText(basename);
    z.addText(exe_path);

    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) return executeSubcommand(
            subcommand,
            allocator,
            arg_iter,
            io,
            system,
            exe_path,
        );
    }

    return error.NoSubcommand;
}

fn executeSubcommand(
    comptime subcommand: type,
    allocator: std.mem.Allocator,
    arg_iter: anytype,
    io: anytype,
    system: zsw.System,
    exe_path: []const u8,
) SubcommandErrors!u8 {
    const z = shared.tracy.traceNamed(@src(), "execute subcommand");
    defer z.end();

    var arg_iterator = shared.ArgIterator(@TypeOf(arg_iter)).init(arg_iter);
    return subcommand.execute(allocator, io, &arg_iterator, system, exe_path) catch |err| switch (err) {
        error.Help => shared.printHelp(subcommand, io, exe_path),
        error.Version => shared.printVersion(subcommand, io),
        else => |narrow_err| narrow_err,
    };
}

pub fn testExecute(comptime subcommand: type, arguments: []const [:0]const u8, settings: anytype) SubcommandErrors!u8 {
    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else VoidWriter.writer();
    const system = if (@hasField(SettingsType, "system")) settings.system else zsw.host_system;

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
        system,
        subcommand.name,
    );
}

pub fn testError(
    comptime subcommand: type,
    arguments: []const [:0]const u8,
    settings: anytype,
    expected_error: []const u8,
) !void {
    const SettingsType = @TypeOf(settings);
    if (@hasField(SettingsType, "stderr")) @compileError("there is already a stderr defined on this settings type");
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const system = if (@hasField(SettingsType, "system")) settings.system else zsw.host_system;

    var stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr.deinit();

    try std.testing.expectEqual(
        @as(u8, 1),
        try testExecute(
            subcommand,
            arguments,
            .{
                .stderr = stderr.writer(),
                .stdin = stdin,
                .stdout = stdout,
                .system = system,
            },
        ),
    );

    try std.testing.expect(std.mem.indexOf(u8, stderr.items, expected_error) != null);
}

pub fn testHelp(comptime subcommand: type, comptime include_shorthand: bool) !void {
    const expected = try std.fmt.allocPrint(std.testing.allocator, subcommand.usage, .{subcommand.name});
    defer std.testing.allocator.free(expected);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    var always_fail_system = try AlwaysFailSystem.init(std.testing.allocator);
    defer always_fail_system.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try testExecute(
            subcommand,
            &.{"--help"},
            .{
                .stdout = out.writer(),
                .system = always_fail_system.backend.system(),
            },
        ),
    );

    try std.testing.expectEqualStrings(expected, out.items);

    if (include_shorthand) {
        out.clearRetainingCapacity();

        try std.testing.expectEqual(
            @as(u8, 0),
            try testExecute(
                subcommand,
                &.{"-h"},
                .{ .stdout = out.writer() },
            ),
        );

        try std.testing.expectEqualStrings(expected, out.items);
    }
}

pub fn testVersion(comptime subcommand: type) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    var always_fail_system = try AlwaysFailSystem.init(std.testing.allocator);
    defer always_fail_system.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try testExecute(
            subcommand,
            &.{"--version"},
            .{
                .stdout = out.writer(),
                .system = always_fail_system.backend.system(),
            },
        ),
    );

    const expected = try std.fmt.allocPrint(std.testing.allocator, shared.version_string, .{subcommand.name});
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, out.items);
}

const AlwaysFailSystem = struct {
    backend: BackendType,

    const BackendType = zsw.Backend(.{ .fallback_to_host = false });

    pub fn init(allocator: std.mem.Allocator) !AlwaysFailSystem {
        var backend = try BackendType.init(allocator, .{});
        errdefer backend.deinit();

        return AlwaysFailSystem{
            .backend = backend,
        };
    }

    pub fn deinit(self: *AlwaysFailSystem) void {
        self.backend.deinit();
    }
};

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
