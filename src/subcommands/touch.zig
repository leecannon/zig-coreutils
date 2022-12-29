const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");
const zsw = @import("zsw");

const log = std.log.scoped(.touch);

pub const name = "touch";

pub const usage =
    \\Usage: {0s} [OPTION]... FILE...
    \\
    \\Update the access and modification times of each FILE to the current time.
    \\
    \\A FILE argument that does not exist is created empty, unless -c or -h is supplied.
    \\
    \\     -a                    change only the access time
    \\     -c, --no-create       do not create any files
    \\     -d, --date=STRING     parse STRING and use it instead of current time
    \\     -f                    (ignored)
    \\     -h, --no-dereference  affect symbolic link instead of any referenced file
    \\     -m                    change only the modification time
    \\     -r, --reference=FILE  use this file's times instead of the current time
    \\     -t STAMP              use [[CC]YY]MMDDhhmm[.ss] instead of current time
    \\     --time=WORD           change the specified time:
    \\                             WORD is access, atime, or use: equivalent to -a
    \\                             WORD is modify or mtime: equivalent to -m
    \\     --help                display this help and exit
    \\     --version             output version information and exit
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

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(false);

    var touch_options: TouchOptions = .{};

    var value_for_shorthand_expected = false;
    var format_string_expected = false;
    var reference_file_expected = false;
    var timestamp_expected = false;

    while (opt_arg) |*arg| : (opt_arg = args.next()) {
        switch (arg.arg_type) {
            .longhand => |longhand| {
                if (value_for_shorthand_expected) {
                    return shared.printInvalidUsage(
                        @This(),
                        io,
                        exe_path,
                        "expected value for previous option",
                    );
                }

                if (std.mem.eql(u8, longhand, "no-create")) {
                    touch_options.create = false;
                    log.debug("got do not create file longhand", .{});
                } else if (std.mem.eql(u8, longhand, "no-dereference")) {
                    touch_options.dereference = false;
                    log.debug("got do not dereference longhand", .{});
                } else {
                    return try shared.printInvalidUsageAlloc(
                        @This(),
                        allocator,
                        io,
                        exe_path,
                        "unrecognized option '--{s}'",
                        .{longhand},
                    );
                }
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (value_for_shorthand_expected) {
                        return shared.printInvalidUsage(
                            @This(),
                            io,
                            exe_path,
                            "expected value for previous option",
                        );
                    }

                    switch (char) {
                        'a' => {
                            touch_options.update = .access_only;
                            log.debug("got access time shorthand", .{});
                        },
                        'c' => {
                            touch_options.create = false;
                            log.debug("got do not create file shorthand", .{});
                        },
                        'd' => {
                            if (shorthand.takeRest()) |rest| {
                                touch_options.time_to_use = .{ .format_string = rest };
                            } else {
                                value_for_shorthand_expected = true;
                                format_string_expected = true;
                            }
                            log.debug("got format string shorthand", .{});
                        },
                        'f' => {}, // ignored
                        'h' => {
                            touch_options.dereference = false;
                            log.debug("got do not dereference shorthand", .{});
                        },
                        'm' => {
                            touch_options.update = .modification_only;
                            log.debug("got modification time shorthand", .{});
                        },
                        'r' => {
                            if (shorthand.takeRest()) |rest| {
                                touch_options.time_to_use = .{ .reference_file = rest };
                            } else {
                                value_for_shorthand_expected = true;
                                reference_file_expected = true;
                            }
                            log.debug("got reference file shorthand", .{});
                        },
                        't' => {
                            if (shorthand.takeRest()) |rest| {
                                touch_options.time_to_use = .{ .timestamp = rest };
                            } else {
                                value_for_shorthand_expected = true;
                                timestamp_expected = true;
                            }
                            log.debug("got timestamp shorthand", .{});
                        },
                        else => return try shared.printInvalidUsageAlloc(
                            @This(),
                            allocator,
                            io,
                            exe_path,
                            "unrecognized option -- '{c}'",
                            .{char},
                        ),
                    }
                }
            },
            .longhand_with_value => |longhand_with_value| {
                if (value_for_shorthand_expected) {
                    return shared.printInvalidUsage(
                        @This(),
                        io,
                        exe_path,
                        "expected value for previous option",
                    );
                }

                if (std.mem.eql(u8, longhand_with_value.longhand, "date")) {
                    touch_options.time_to_use = .{ .format_string = longhand_with_value.value };
                    log.debug("got format string longhand, format string: '{s}'", .{longhand_with_value.value});
                } else if (std.mem.eql(u8, longhand_with_value.longhand, "reference")) {
                    touch_options.time_to_use = .{ .reference_file = longhand_with_value.value };
                    log.debug("got reference file longhand, reference file: '{s}'", .{longhand_with_value.value});
                } else if (std.mem.eql(u8, longhand_with_value.longhand, "time")) {
                    log.debug("got time longhand, value: '{s}'", .{longhand_with_value.value});

                    if (std.mem.eql(u8, longhand_with_value.value, "access") or
                        std.mem.eql(u8, longhand_with_value.value, "atime") or
                        std.mem.eql(u8, longhand_with_value.value, "use"))
                    {
                        touch_options.update = .access_only;
                    } else if (std.mem.eql(u8, longhand_with_value.value, "modify") or
                        std.mem.eql(u8, longhand_with_value.value, "mtime"))
                    {
                        touch_options.update = .modification_only;
                    } else {
                        return try shared.printInvalidUsageAlloc(
                            @This(),
                            allocator,
                            io,
                            exe_path,
                            "unrecognized value for time option '{s}'",
                            .{longhand_with_value.value},
                        );
                    }
                } else {
                    return try shared.printInvalidUsageAlloc(
                        @This(),
                        allocator,
                        io,
                        exe_path,
                        "unrecognized option '--{s}'",
                        .{longhand_with_value.longhand},
                    );
                }
            },
            .positional => {
                if (value_for_shorthand_expected) {
                    if (format_string_expected) {
                        touch_options.time_to_use = .{ .format_string = arg.raw };
                        log.debug("got format string value: '{s}'", .{arg.raw});
                        format_string_expected = false;
                    } else if (reference_file_expected) {
                        touch_options.time_to_use = .{ .reference_file = arg.raw };
                        log.debug("got reference file value: '{s}'", .{arg.raw});
                        reference_file_expected = false;
                    } else if (timestamp_expected) {
                        touch_options.time_to_use = .{ .timestamp = arg.raw };
                        log.debug("got timestamp value: '{s}'", .{arg.raw});
                        timestamp_expected = false;
                    } else {
                        return shared.printInvalidUsage(
                            @This(),
                            io,
                            exe_path,
                            "expected value for previous option",
                        );
                    }

                    value_for_shorthand_expected = false;
                    continue;
                }

                return performTouch(allocator, io, args, system, arg.raw, touch_options);
            },
        }
    }

    return shared.printInvalidUsage(@This(), io, exe_path, "missing file operand");
}

fn performTouch(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    system: zsw.System,
    first_file_path: []const u8,
    options: TouchOptions,
) !u8 {
    const z = shared.tracy.traceNamed(@src(), "perform touch");
    defer z.end();

    log.debug("performTouch called, first_file_path='{s}', options={}", .{ first_file_path, options });

    const times = getTimes(allocator, io, system, options.time_to_use) catch return 1;

    log.debug("times to be used for touch: {}", .{times});

    var opt_file_path: ?[]const u8 = first_file_path;

    const cwd = system.cwd();

    while (opt_file_path) |file_path| : (opt_file_path = args.nextRaw()) {
        const file_zone = shared.tracy.traceNamed(@src(), "process file");
        defer file_zone.end();
        file_zone.addText(file_path);

        const file: zsw.File = switch (options.create) {
            true => cwd.createFile(file_path, .{}),
            false => cwd.openFile(file_path, .{}),
        } catch |err|
            return shared.printErrorAlloc(
            @This(),
            allocator,
            io,
            "failed to open '{s}': {s}",
            .{ file_path, @errorName(err) },
        );
        defer file.close();

        (if (options.update == .both)
            file.updateTimes(times.access_time, times.modification_time)
        else blk: {
            const stat = file.stat() catch |err|
                return shared.printErrorAlloc(
                @This(),
                allocator,
                io,
                "failed to stat '{s}': {s}",
                .{ file_path, @errorName(err) },
            );

            break :blk switch (options.update) {
                .both => unreachable,
                .access_only => file.updateTimes(times.access_time, stat.mtime),
                .modification_only => file.updateTimes(stat.atime, times.modification_time),
            };
        }) catch |err|
            return shared.printErrorAlloc(
            @This(),
            allocator,
            io,
            "failed to update times on '{s}': {s}",
            .{ file_path, @errorName(err) },
        );
    }

    return 0;
}

fn getTimes(
    allocator: std.mem.Allocator,
    io: anytype,
    system: zsw.System,
    time_to_use: TouchOptions.TimeToUse,
) !FileTimes {
    switch (time_to_use) {
        .current_time => {
            const time = system.nanoTimestamp();
            return .{
                .access_time = time,
                .modification_time = time,
            };
        },
        .reference_file => |reference_file_path| {
            const reference_file = system.cwd().openFile(reference_file_path, .{}) catch |err| {
                _ = shared.printErrorAlloc(
                    @This(),
                    allocator,
                    io,
                    "unable to open '{s}': {s}",
                    .{ reference_file_path, @errorName(err) },
                ) catch |e| return e;
                return err;
            };
            defer reference_file.close();
            const stat = reference_file.stat() catch |err| {
                _ = shared.printErrorAlloc(
                    @This(),
                    allocator,
                    io,
                    "unable to stat '{s}': {s}",
                    .{ reference_file_path, @errorName(err) },
                ) catch |e| return e;
                return err;
            };

            return .{
                .access_time = stat.atime,
                .modification_time = stat.mtime,
            };
        },
        .format_string => @panic("date format string is not implemented"), // TODO
        .timestamp => @panic("timestamp is not implemented"), // TODO
    }
}

const FileTimes = struct {
    access_time: i128,
    modification_time: i128,
};

const TouchOptions = struct {
    update: Update = .both,
    create: bool = true,
    dereference: bool = true,
    time_to_use: TimeToUse = .current_time,

    pub const Update = enum {
        both,
        access_only,
        modification_only,
    };

    pub const TimeToUse = union(enum) {
        current_time,
        format_string: []const u8,
        reference_file: []const u8,
        timestamp: []const u8,
    };

    pub fn format(
        value: TouchOptions,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        try writer.writeAll("TouchOptions{ .update = .");
        try writer.writeAll(@tagName(value.update));
        try writer.writeAll(", .create = ");
        try (if (value.create) writer.writeAll("true") else writer.writeAll("false"));
        try writer.writeAll(", .dereference = ");
        try (if (value.dereference) writer.writeAll("true") else writer.writeAll("false"));
        try writer.writeAll(", .time_to_use = ");
        switch (value.time_to_use) {
            .current_time => try writer.writeAll(".current_time }"),
            inline else => |val| try writer.print(".{{ .{s} = \"{s}\" }} }}", .{ @tagName(value.time_to_use), val }),
        }
    }
};

// test "touch - create file" {
//     var nano_timestamp: i128 = 1000;

//     var test_system = try TestSystem.init(&nano_timestamp);
//     defer test_system.deinit();

//     const system = test_system.backend.system();

//     // file should not exist
//     try std.testing.expectError(
//         error.FileNotFound,
//         system.cwd().openFile("FILE", .{}),
//     );

//     const ret = try subcommands.testExecute(
//         @This(),
//         &.{"FILE"},
//         .{ .system = system },
//     );
//     try std.testing.expect(ret == 0);

//     // file should exist
//     const file = try system.cwd().openFile("FILE", .{});
//     defer file.close();

//     var stat = try file.stat();
//     try std.testing.expectEqual(nano_timestamp, stat.atime);
//     try std.testing.expectEqual(nano_timestamp, stat.mtime);
// }

test "touch - don't create file" {
    var nano_timestamp: i128 = 1000;

    var test_system = try TestSystem.create(&nano_timestamp);
    defer test_system.destroy();

    const system = test_system.backend.system();

    // file should not exist
    try std.testing.expectError(
        error.FileNotFound,
        system.cwd().openFile("FILE", .{}),
    );

    try subcommands.testError(
        @This(),
        &.{ "-c", "FILE" },
        .{},
        "failed to open",
    );
}

test "touch - atime only flag" {
    var nano_timestamp: i128 = 1000;

    var test_system = try TestSystem.create(&nano_timestamp);
    defer test_system.destroy();

    const system = test_system.backend.system();

    @atomicStore(i128, &nano_timestamp, 2000, .Monotonic);

    const ret = try subcommands.testExecute(
        @This(),
        &.{ "-a", "EXISTS" },
        .{ .system = system },
    );
    try std.testing.expect(ret == 0);

    const file = try system.cwd().openFile("EXISTS", .{});
    defer file.close();

    const stat = try file.stat();
    try std.testing.expectEqual(@as(i128, 2000), stat.atime);
    try std.testing.expectEqual(@as(i128, 1000), stat.mtime);
}

test "touch - mtime only flag" {
    var nano_timestamp: i128 = 1000;

    var test_system = try TestSystem.create(&nano_timestamp);
    defer test_system.destroy();

    const system = test_system.backend.system();

    @atomicStore(i128, &nano_timestamp, 2000, .Monotonic);

    const ret = try subcommands.testExecute(
        @This(),
        &.{ "-m", "EXISTS" },
        .{ .system = system },
    );
    try std.testing.expect(ret == 0);

    const file = try system.cwd().openFile("EXISTS", .{});
    defer file.close();

    const stat = try file.stat();
    try std.testing.expectEqual(@as(i128, 1000), stat.atime);
    try std.testing.expectEqual(@as(i128, 2000), stat.mtime);
}

test "touch no args" {
    try subcommands.testError(
        @This(),
        &.{},
        .{},
        "missing file operand",
    );
}

test "touch help" {
    try subcommands.testHelp(@This(), false);
}

test "touch version" {
    try subcommands.testVersion(@This());
}

const TestSystem = struct {
    backend: *BackendType,

    const BackendType = zsw.Backend(.{
        .fallback_to_host = false,
        .file_system = true,
        .time = true,
    });

    pub fn create(nano_timestamp: *const i128) !TestSystem {
        const file_system = try zsw.FileSystemDescription.create(std.testing.allocator);
        defer file_system.destroy();
        try file_system.root.addFile("EXISTS", "");

        const time = zsw.TimeDescription{ .nano_timestamp = nano_timestamp };

        const backend = try BackendType.create(std.testing.allocator, .{
            .file_system = file_system,
            .time = time,
        });
        errdefer backend.destroy();

        return .{ .backend = backend };
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
