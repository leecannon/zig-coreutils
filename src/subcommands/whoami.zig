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
//     fn nextWithHelpOrVersion(self: *Self, comptime include_shorthand: bool) !?shared.Arg,
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

    // Only the first argument is checked for help or version
    _ = try args.nextWithHelpOrVersion(true);

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

test "whoami root" {
    var test_system = try TestSystem.create();
    defer test_system.destroy();

    // set the effective user id to root
    test_system.backend.linux_user_group.euid = 0;

    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    const ret = try subcommands.testExecute(
        @This(),
        &.{},
        .{
            .system = test_system.backend.system(),
            .stdout = stdout.writer(),
        },
    );

    try std.testing.expect(ret == 0);
    try std.testing.expectEqualStrings("root\n", stdout.items);
}

test "whoami user" {
    var test_system = try TestSystem.create();
    defer test_system.destroy();

    var stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout.deinit();

    const ret = try subcommands.testExecute(
        @This(),
        &.{},
        .{
            .system = test_system.backend.system(),
            .stdout = stdout.writer(),
        },
    );

    try std.testing.expect(ret == 0);
    try std.testing.expectEqualStrings("user\n", stdout.items);
}

test "whoami help" {
    try subcommands.testHelp(@This(), true);
}

test "whoami version" {
    try subcommands.testVersion(@This());
}

const TestSystem = struct {
    backend: *BackendType,

    const BackendType = zsw.Backend(.{
        .fallback_to_host = true,
        .file_system = true,
        .linux_user_group = true,
    });

    pub fn create() !TestSystem {
        const file_system = blk: {
            const file_system = try zsw.FileSystemDescription.create(std.testing.allocator);
            errdefer file_system.destroy();

            const etc = try file_system.root.addDirectory("etc");

            try etc.addFile(
                "passwd",
                \\root:x:0:0::/root:/bin/bash
                \\bin:x:1:1::/:/usr/bin/nologin
                \\daemon:x:2:2::/:/usr/bin/nologin
                \\mail:x:8:12::/var/spool/mail:/usr/bin/nologin
                \\ftp:x:14:11::/srv/ftp:/usr/bin/nologin
                \\http:x:33:33::/srv/http:/usr/bin/nologin
                \\nobody:x:65534:65534:Nobody:/:/usr/bin/nologin
                \\user:x:1000:1001:User:/home/user:/bin/bash
                \\
                ,
            );

            break :blk file_system;
        };
        defer file_system.destroy();

        var linux_user_group: zsw.LinuxUserGroupDescription = .{
            .initial_euid = 1000,
        };

        var backend = try BackendType.create(std.testing.allocator, .{
            .file_system = file_system,
            .linux_user_group = linux_user_group,
        });
        errdefer backend.destroy();

        return TestSystem{
            .backend = backend,
        };
    }

    pub fn destroy(self: *TestSystem) void {
        self.backend.destroy();
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
