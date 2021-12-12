const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const zsw = @import("zsw");

const log = std.log.scoped(.groups);

pub const name = "groups";

pub const usage =
    \\Usage: {0s} [user]
    \\   or: {0s} OPTION
    \\
    \\Display the current group names. 
    \\The optional [user] parameter will display the groups for the named user.
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
    \\
;

// io
// .{
//     .stderr: std.io.Writer,
//     .stdin: std.io.Reader,
//     .stdout: std.io.Writer,
// },

// args
// struct {
//     fn next(self: *Self) ?shared.Arg,
//
//     // intended to only be called for the first argument
//     fn nextWithHelpOrVersion(self: *Self) !?shared.Arg,
//
//     fn nextRaw(self: *Self) ?[]const u8,
// }

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    system: zsw.System,
    exe_path: []const u8,
) subcommands.Error!u8 {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = exe_path;

    const opt_arg = try args.nextWithHelpOrVersion();

    const passwd_file = system.cwd().openFile("/etc/passwd", .{}) catch {
        return shared.printError(@This(), io, "unable to read '/etc/passwd'");
    };
    defer if (shared.free_on_close) passwd_file.close();

    return if (opt_arg) |arg|
        otherUser(allocator, io, arg, passwd_file, system)
    else
        currentUser(allocator, io, passwd_file, system);
}

fn currentUser(
    allocator: std.mem.Allocator,
    io: anytype,
    passwd_file: zsw.File,
    system: zsw.System,
) subcommands.Error!u8 {
    const z = shared.tracy.traceNamed(@src(), "current user");
    defer z.end();

    log.info("currentUser called", .{});

    const euid = std.os.linux.geteuid();

    var passwd_buffered_reader = std.io.bufferedReader(passwd_file.reader());
    const passwd_reader = passwd_buffered_reader.reader();

    var line_buffer = std.ArrayList(u8).init(allocator);
    defer if (shared.free_on_close) line_buffer.deinit();

    while (true) {
        passwd_reader.readUntilDelimiterArrayList(&line_buffer, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return shared.printError(@This(), io, "unable to read '/etc/passwd'"),
        };

        var column_iter = std.mem.tokenize(u8, line_buffer.items, ":");

        const user_name = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        const user_id_slice = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        if (std.fmt.parseUnsigned(std.os.uid_t, user_id_slice, 10)) |user_id| {
            if (user_id == euid) {
                log.debug("found matching user id: {}", .{user_id});

                const primary_group_id_slice = column_iter.next() orelse
                    return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

                if (std.fmt.parseUnsigned(std.os.uid_t, primary_group_id_slice, 10)) |primary_group_id| {
                    return printGroups(allocator, user_name, primary_group_id, io, system);
                } else |_| {
                    return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");
                }
            } else {
                log.debug("found non-matching user id: {}", .{user_id});
            }
        } else |_| {
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");
        }
    }

    return shared.printError(@This(), io, "'/etc/passwd' does not contain the current effective uid");
}

fn otherUser(
    allocator: std.mem.Allocator,
    io: anytype,
    arg: shared.Arg,
    passwd_file: zsw.File,
    system: zsw.System,
) subcommands.Error!u8 {
    const z = shared.tracy.traceNamed(@src(), "other user");
    defer z.end();
    z.addText(arg.raw);

    log.info("otherUser called, arg='{s}'", .{arg.raw});

    var passwd_buffered_reader = std.io.bufferedReader(passwd_file.reader());
    const passwd_reader = passwd_buffered_reader.reader();

    var line_buffer = std.ArrayList(u8).init(allocator);
    defer if (shared.free_on_close) line_buffer.deinit();

    while (true) {
        passwd_reader.readUntilDelimiterArrayList(&line_buffer, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return shared.printError(@This(), io, "unable to read '/etc/passwd'"),
        };

        var column_iter = std.mem.tokenize(u8, line_buffer.items, ":");

        const user_name = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        if (!std.mem.eql(u8, user_name, arg.raw)) {
            log.debug("found non-matching user: {s}", .{user_name});
            continue;
        }

        log.debug("found matching user: {s}", .{user_name});

        // skip password stand-in
        _ = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        // skip user id
        _ = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        const primary_group_id_slice = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");

        if (std.fmt.parseUnsigned(std.os.uid_t, primary_group_id_slice, 10)) |primary_group_id| {
            return printGroups(allocator, user_name, primary_group_id, io, system);
        } else |_| {
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");
        }
    }

    return shared.printError(@This(), io, "'/etc/passwd' does not contain the current effective uid");
}

fn printGroups(
    allocator: std.mem.Allocator,
    user_name: []const u8,
    primary_group_id: std.os.uid_t,
    io: anytype,
    system: zsw.System,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "print groups");
    defer z.end();
    z.addText(user_name);

    log.info("printGroups called, user_name='{s}', primary_group_id={}", .{ user_name, primary_group_id });

    var group_file = system.cwd().openFile("/etc/group", .{}) catch {
        return shared.printError(@This(), io, "unable to read '/etc/group'");
    };
    defer if (shared.free_on_close) group_file.close();

    var group_buffered_reader = std.io.bufferedReader(group_file.reader());
    const group_reader = group_buffered_reader.reader();

    var line_buffer = std.ArrayList(u8).init(allocator);
    defer if (shared.free_on_close) line_buffer.deinit();

    var first = true;

    while (true) {
        group_reader.readUntilDelimiterArrayList(&line_buffer, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return shared.printError(@This(), io, "unable to read '/etc/group'"),
        };

        var column_iter = std.mem.tokenize(u8, line_buffer.items, ":");

        const group_name = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/group' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/group' is invalid");

        const group_id_slice = column_iter.next() orelse
            return shared.printError(@This(), io, "format of '/etc/group' is invalid");

        if (std.fmt.parseUnsigned(std.os.uid_t, group_id_slice, 10)) |group_id| {
            if (group_id == primary_group_id) {
                if (!first) {
                    io.stdout.writeByte(' ') catch |err| shared.unableToWriteTo("stdout", io, err);
                }
                io.stdout.writeAll(group_name) catch |err| shared.unableToWriteTo("stdout", io, err);
                first = false;
                continue;
            }
        } else |_| {
            return shared.printError(@This(), io, "format of '/etc/group' is invalid");
        }

        const members = column_iter.next() orelse continue;
        if (members.len == 0) continue;

        var member_iter = std.mem.tokenize(u8, members, ",");
        while (member_iter.next()) |member| {
            if (std.mem.eql(u8, member, user_name)) {
                if (!first) {
                    io.stdout.writeByte(' ') catch |err| shared.unableToWriteTo("stdout", io, err);
                }
                io.stdout.writeAll(group_name) catch |err| shared.unableToWriteTo("stdout", io, err);
                first = false;
                break;
            }
        }
    }

    io.stdout.writeByte('\n') catch |err| shared.unableToWriteTo("stdout", io, err);

    return 0;
}

test "groups no args" {
    var test_system = TestSystem.init();
    defer test_system.deinit();

    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            @This(),
            &.{},
            .{
                .system = test_system.backend.system(),
            },
        ),
    );
}

test "groups help" {
    try subcommands.testHelp(@This());
}

test "groups version" {
    try subcommands.testVersion(@This());
}

const TestSystem = struct {
    backend: zsw.CustomBackend(.{}),

    pub fn init() TestSystem {
        return .{
            .backend = zsw.CustomBackend(.{}).init(
                std.testing.allocator,
            ),
        };
    }

    pub fn deinit(self: *TestSystem) void {
        self.backend.deinit();
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
