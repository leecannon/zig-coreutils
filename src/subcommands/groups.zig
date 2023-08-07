const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.groups);

pub const name = "groups";

pub const short_help =
    \\Usage: {0s} [user]
    \\   or: {0s} OPTION
    \\
    \\Display the current group names. 
    \\The optional [user] parameter will display the groups for the named user.
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
;

// No examples provided for `groups`
// TODO: Should there be? https://github.com/leecannon/zig-coreutils/issues/3
pub const extended_help = "";

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = exe_path;

    const opt_arg = try args.nextWithHelpOrVersion(true);

    const passwd_file = try shared.mapFile(@This(), allocator, io, cwd, "/etc/passwd");
    defer passwd_file.close();

    if (opt_arg) |arg| return otherUser(allocator, io, arg, passwd_file.file_contents, cwd);

    return currentUser(allocator, io, passwd_file.file_contents, cwd);
}

fn currentUser(
    allocator: std.mem.Allocator,
    io: anytype,
    passwd_file_contents: []const u8,
    cwd: std.fs.Dir,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), "current user");
    defer z.end();

    const euid = std.os.linux.geteuid();

    log.debug("currentUser called, euid: {}", .{euid});

    var passwd_file_iter = shared.passwdFileIterator(passwd_file_contents);

    while (try passwd_file_iter.next(@This(), io)) |entry| {
        const user_id = std.fmt.parseUnsigned(std.os.uid_t, entry.user_id, 10) catch {
            return shared.printError(
                @This(),
                io,
                "format of '/etc/passwd' is invalid",
            );
        };

        if (user_id != euid) {
            log.debug("found non-matching user id: {}", .{user_id});
            continue;
        }

        log.debug("found matching user id: {}", .{user_id});

        const primary_group_id = std.fmt.parseUnsigned(std.os.uid_t, entry.primary_group_id, 10) catch {
            return shared.printError(
                @This(),
                io,
                "format of '/etc/passwd' is invalid",
            );
        };

        return printGroups(allocator, entry.user_name, primary_group_id, io, cwd);
    }

    return shared.printError(
        @This(),
        io,
        "'/etc/passwd' does not contain the current effective uid",
    );
}

fn otherUser(
    allocator: std.mem.Allocator,
    io: anytype,
    arg: shared.Arg,
    passwd_file_contents: []const u8,
    cwd: std.fs.Dir,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), "other user");
    defer z.end();
    z.addText(arg.raw);

    log.debug("otherUser called, arg='{s}'", .{arg.raw});

    var passwd_file_iter = shared.passwdFileIterator(passwd_file_contents);

    while (try passwd_file_iter.next(@This(), io)) |entry| {
        if (!std.mem.eql(u8, entry.user_name, arg.raw)) {
            log.debug("found non-matching user: {s}", .{entry.user_name});
            continue;
        }

        log.debug("found matching user: {s}", .{entry.user_name});

        const primary_group_id = std.fmt.parseUnsigned(std.os.uid_t, entry.primary_group_id, 10) catch {
            return shared.printError(
                @This(),
                io,
                "format of '/etc/passwd' is invalid",
            );
        };

        return printGroups(allocator, entry.user_name, primary_group_id, io, cwd);
    }

    return shared.printErrorAlloc(@This(), allocator, io, "unknown user {s}", .{arg.raw});
}

fn printGroups(
    allocator: std.mem.Allocator,
    user_name: []const u8,
    primary_group_id: std.os.uid_t,
    io: anytype,
    cwd: std.fs.Dir,
) !void {
    const z = shared.tracy.traceNamed(@src(), "print groups");
    defer z.end();
    z.addText(user_name);

    log.debug("printGroups called, user_name='{s}', primary_group_id={}", .{ user_name, primary_group_id });

    const group_file = try shared.mapFile(@This(), allocator, io, cwd, "/etc/group");
    defer group_file.close();

    var group_file_iter = shared.groupFileIterator(group_file.file_contents);

    var first = true;

    while (try group_file_iter.next(@This(), io)) |entry| {
        const group_id = std.fmt.parseUnsigned(std.os.uid_t, entry.group_id, 10) catch {
            return shared.printError(
                @This(),
                io,
                "format of '/etc/group' is invalid",
            );
        };

        if (group_id == primary_group_id) {
            if (!first) {
                io.stdout.writeByte(' ') catch |err| return shared.unableToWriteTo("stdout", io, err);
            }
            io.stdout.writeAll(entry.group_name) catch |err| return shared.unableToWriteTo("stdout", io, err);

            first = false;
            continue;
        }

        var member_iter = entry.iterateMembers();
        while (member_iter.next()) |member| {
            if (!std.mem.eql(u8, member, user_name)) continue;

            if (!first) {
                io.stdout.writeByte(' ') catch |err| return shared.unableToWriteTo("stdout", io, err);
            }

            io.stdout.writeAll(entry.group_name) catch |err| return shared.unableToWriteTo("stdout", io, err);
            first = false;
            break;
        }
    }

    io.stdout.writeByte('\n') catch |err| return shared.unableToWriteTo("stdout", io, err);
}

// TODO: How do we test this without introducing the amount of complexity that https://github.com/leecannon/zsw does?
// https://github.com/leecannon/zig-coreutils/issues/1

test "groups help" {
    try subcommands.testHelp(@This(), true);
}

test "groups version" {
    try subcommands.testVersion(@This());
}

const help_zls = struct {
    // Due to https://github.com/zigtools/zls/pull/1067 this is enough to help ZLS understand the `io` and `args` arguments

    fn dummyExecute() void {
        execute(
            undefined,
            @as(DummyIO, undefined),
            @as(DummyArgs, undefined),
            undefined,
            undefined,
        );
        @panic("THIS SHOULD NEVER BE CALLED");
    }

    const DummyIO = struct {
        stderr: std.io.Writer,
        stdin: std.io.Reader,
        stdout: std.io.Writer,
    };

    const DummyArgs = struct {
        const Self = @This();

        fn next(self: *Self) ?shared.Arg {
            _ = self;
            @panic("THIS SHOULD NEVER BE CALLED");
        }

        /// intended to only be called for the first argument
        fn nextWithHelpOrVersion(self: *Self, comptime include_shorthand: bool) !?shared.Arg {
            _ = include_shorthand;
            _ = self;
            @panic("THIS SHOULD NEVER BE CALLED");
        }

        fn nextRaw(self: *Self) ?[]const u8 {
            _ = self;
            @panic("THIS SHOULD NEVER BE CALLED");
        }
    };
};

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
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
