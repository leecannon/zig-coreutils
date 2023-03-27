const std = @import("std");
const shared = @import("shared.zig");
const builtin = @import("builtin");

const log = std.log.scoped(.subcommand);

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/basename.zig"),
    @import("subcommands/clear.zig"),
    @import("subcommands/dirname.zig"),
    @import("subcommands/false.zig"),
    @import("subcommands/groups.zig"),
    @import("subcommands/nproc.zig"),
    @import("subcommands/touch.zig"),
    @import("subcommands/true.zig"),
    @import("subcommands/whoami.zig"),
    @import("subcommands/yes.zig"),
};

pub const ExecuteError = error{
    NoSubcommand,
} || SubcommandError;

const SubcommandError = error{
    OutOfMemory,
    UnableToParseArguments,
    AlreadyHandled,
};

const SubcommandNonError = error{
    ShortHelp,
    FullHelp,
    Version,
};

pub const Error = SubcommandError || SubcommandNonError;

pub fn execute(
    allocator: std.mem.Allocator,
    arg_iter: *std.process.ArgIterator,
    io: anytype,
    basename: []const u8,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) ExecuteError!void {
    const z = shared.tracy.traceNamed(@src(), "execute");
    defer z.end();

    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) {
            z.addText(basename);
            return executeSubcommand(
                subcommand,
                allocator,
                arg_iter,
                io,
                cwd,
                exe_path,
            );
        }
    }

    // if the basename of the executable does not match any of the subcommands then try
    // to use the first argument as the subcommand name
    if (arg_iter.next()) |possible_subcommand| {
        log.debug("no subcommand found matching basename '{s}', trying first argument '{s}'", .{
            basename,
            possible_subcommand,
        });

        inline for (SUBCOMMANDS) |subcommand| {
            if (std.mem.eql(u8, subcommand.name, possible_subcommand)) {
                z.addText(possible_subcommand);

                const exe_path_with_subcommand = try std.fmt.allocPrint(allocator, "{s} {s}", .{
                    exe_path,
                    subcommand.name,
                });
                defer if (shared.free_on_close) allocator.free(exe_path_with_subcommand);

                return executeSubcommand(
                    subcommand,
                    allocator,
                    arg_iter,
                    io,
                    cwd,
                    exe_path_with_subcommand,
                );
            }
        }
    }

    return error.NoSubcommand;
}

fn executeSubcommand(
    comptime subcommand: type,
    allocator: std.mem.Allocator,
    arg_iter: anytype,
    io: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) SubcommandError!void {
    const z = shared.tracy.traceNamed(@src(), "execute subcommand");
    defer z.end();

    log.debug("executing subcommand '{s}'", .{subcommand.name});

    var arg_iterator = shared.ArgIterator(@TypeOf(arg_iter)).init(arg_iter);
    return subcommand.execute(allocator, io, &arg_iterator, cwd, exe_path) catch |err| switch (err) {
        error.ShortHelp => shared.printShortHelp(subcommand, io, exe_path),
        error.FullHelp => shared.printFullHelp(subcommand, io, exe_path),
        error.Version => shared.printVersion(subcommand, io),
        else => |narrow_err| narrow_err,
    };
}

pub fn testExecute(comptime subcommand: type, arguments: []const [:0]const u8, settings: anytype) SubcommandError!void {
    const SettingsType = @TypeOf(settings);
    const stdin = if (@hasField(SettingsType, "stdin")) settings.stdin else VoidReader.reader();
    const stdout = if (@hasField(SettingsType, "stdout")) settings.stdout else VoidWriter.writer();
    const stderr = if (@hasField(SettingsType, "stderr")) settings.stderr else VoidWriter.writer();

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

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
        cwd,
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

    const cwd_provided = @hasField(SettingsType, "cwd");
    var tmp_dir = if (!cwd_provided) std.testing.tmpDir(.{}) else {};
    defer if (!cwd_provided) tmp_dir.cleanup();
    const cwd = if (cwd_provided) settings.cwd else tmp_dir.dir;

    var stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr.deinit();

    try std.testing.expectError(error.AlreadyHandled, testExecute(
        subcommand,
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

pub fn testHelp(comptime subcommand: type, comptime include_shorthand: bool) !void {
    const full_expected_help = try std.fmt.allocPrint(
        std.testing.allocator,
        comptime subcommand.short_help ++ subcommand.extended_help,
        .{subcommand.name},
    );
    defer std.testing.allocator.free(full_expected_help);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try testExecute(
        subcommand,
        &.{"--help"},
        .{ .stdout = out.writer() },
    );

    try std.testing.expectEqualStrings(full_expected_help, out.items);

    if (include_shorthand) {
        const short_expected_help = try std.fmt.allocPrint(
            std.testing.allocator,
            subcommand.short_help,
            .{subcommand.name},
        );
        defer std.testing.allocator.free(short_expected_help);

        out.clearRetainingCapacity();

        try testExecute(
            subcommand,
            &.{"-h"},
            .{ .stdout = out.writer() },
        );

        try std.testing.expectEqualStrings(short_expected_help, out.items);
    }
}

pub fn testVersion(comptime subcommand: type) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try testExecute(
        subcommand,
        &.{"--version"},
        .{
            .stdout = out.writer(),
        },
    );

    const expected = try std.fmt.allocPrint(std.testing.allocator, shared.version_string, .{subcommand.name});
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

comptime {
    if (@import("builtin").is_test) _ = @import("subcommands/template.zig");
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
