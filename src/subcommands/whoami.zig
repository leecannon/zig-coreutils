const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

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
//     fn nextWithHelpOrVersion(self: *Self, comptime include_shorthand: bool) !?shared.Arg,
//
//     fn nextRaw(self: *Self) ?[]const u8,
// }

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

    // Only the first argument is checked for help or version
    _ = try args.nextWithHelpOrVersion(true);

    const euid = std.os.linux.geteuid();

    const passwd_file = try shared.mapFile(@This(), allocator, io, cwd, "/etc/passwd");
    defer passwd_file.close();

    var passwd_file_iter = shared.passwdFileIterator(passwd_file.file_contents);

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

        io.stdout.print("{s}\n", .{entry.user_name}) catch |err| {
            return shared.unableToWriteTo(
                "stdout",
                io,
                err,
            );
        };
        return;
    }

    return shared.printError(
        @This(),
        io,
        "'/etc/passwd' does not contain the current effective uid",
    );
}

// TODO: How do we test this without introducing the amount of complexity that https://github.com/leecannon/zsw does?

test "whoami help" {
    try subcommands.testHelp(@This(), true);
}

test "whoami version" {
    try subcommands.testVersion(@This());
}

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
