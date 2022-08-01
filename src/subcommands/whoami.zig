const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const zsw = @import("zsw");

const log = std.log.scoped(.whoami);

pub const name = "whoami";

pub const usage =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Print the user name for the current effective user id.
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

    _ = io;
    _ = exe_path;
    _ = system;
    _ = allocator;

    // Only the first argument is checked for help or version
    _ = try args.nextWithHelpOrVersion();

    const passwd_file = system.cwd().openFile("/etc/passwd", .{}) catch {
        return shared.printError(@This(), io, "unable to read '/etc/passwd'");
    };
    defer if (shared.free_on_close) passwd_file.close();

    const euid = system.geteuid();

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

                io.stdout.print("{s}\n", .{user_name}) catch |err| shared.unableToWriteTo("stdout", io, err);
                return 0;
            } else {
                log.debug("found non-matching user id: {}", .{user_id});
            }
        } else |_| {
            return shared.printError(@This(), io, "format of '/etc/passwd' is invalid");
        }
    }

    return shared.printError(@This(), io, "'/etc/passwd' does not contain the current effective uid");
}

test "whoami no args" {
    try std.testing.expectEqual(
        @as(u8, 0),
        try subcommands.testExecute(
            @This(),
            &.{},
            .{},
        ),
    );
}

test "whoami help" {
    try subcommands.testHelp(@This());
}

test "whoami version" {
    try subcommands.testVersion(@This());
}

comptime {
    std.testing.refAllDecls(@This());
}
