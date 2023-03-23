const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.touch);

pub const name = "touch";

pub const usage =
    \\Usage: {0s} [OPTION]... FILE...
    \\
    \\Update the access and modification times of each FILE to the current time.
    \\
    \\A FILE argument that does not exist is created empty, unless -c or -h is supplied.
    \\
    \\A FILE argument string of '-' is handled specially and causes 'touch' to change 
    \\the times of the file associated with standard output.
    \\
    \\     -a                    change only the access time
    \\     -c, --no-create       do not create any files
    \\     -f                    (ignored)
    \\     -h, --no-dereference  affect symbolic link instead of any referenced file
    \\     -m                    change only the modification time
    \\     -r, --reference=FILE  use this file's times instead of the current time
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
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    const options = try parseArguments(allocator, io, args, exe_path);

    return performTouch(allocator, io, args, options, cwd);
}

fn parseArguments(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    exe_path: []const u8,
) !TouchOptions {
    const z = shared.tracy.traceNamed(@src(), "parse arguments");
    defer z.end();

    var opt_arg: ?shared.Arg = try args.nextWithHelpOrVersion(false);

    var touch_options: TouchOptions = .{};

    const State = union(enum) {
        normal,
        reference_file,
        time,
        time_argument: []const u8,
        invalid_argument: Argument,

        const Argument = union(enum) {
            slice: []const u8,
            character: u8,
        };
    };

    var state: State = .normal;

    while (opt_arg) |*arg| : (opt_arg = args.next()) {
        switch (arg.arg_type) {
            .longhand => |longhand| {
                if (state != .normal) break;

                if (std.mem.eql(u8, longhand, "no-create")) {
                    touch_options.create = false;
                    log.debug("got do not create file longhand", .{});
                } else if (std.mem.eql(u8, longhand, "no-dereference")) {
                    touch_options.dereference = false;
                    log.debug("got do not dereference longhand", .{});
                } else if (std.mem.eql(u8, longhand, "reference-file")) {
                    state = .reference_file;
                    log.debug("got reference file longhand", .{});
                } else if (std.mem.eql(u8, longhand, "time")) {
                    state = .time;
                    log.debug("got time longhand", .{});
                } else {
                    state = .{ .invalid_argument = .{ .slice = longhand } };
                    break;
                }
            },
            .shorthand => |*shorthand| {
                while (shorthand.next()) |char| {
                    if (state != .normal) break;

                    switch (char) {
                        'a' => {
                            touch_options.update = .access_only;
                            log.debug("got access time shorthand", .{});
                        },
                        'c' => {
                            touch_options.create = false;
                            log.debug("got do not create file shorthand", .{});
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
                            if (shorthand.takeRest()) |rest|
                                touch_options.time_to_use = .{ .reference_file = rest }
                            else
                                state = .reference_file;

                            log.debug("got reference file shorthand", .{});
                        },
                        else => {
                            state = .{ .invalid_argument = .{ .character = char } };
                            break;
                        },
                    }
                }
            },
            .longhand_with_value => |longhand_with_value| {
                if (state != .normal) break;

                if (std.mem.eql(u8, longhand_with_value.longhand, "reference")) {
                    touch_options.time_to_use = .{ .reference_file = longhand_with_value.value };
                    log.debug("got reference file longhand, reference file: '{s}'", .{longhand_with_value.value});
                } else if (std.mem.eql(u8, longhand_with_value.longhand, "time")) {
                    log.debug("got time longhand, value: '{s}'", .{longhand_with_value.value});
                    touch_options.update = parseTimeArgument(longhand_with_value.value) orelse {
                        state = .{ .time_argument = longhand_with_value.value };
                        break;
                    };
                } else {
                    state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                    break;
                }
            },
            .positional => {
                switch (state) {
                    .normal => {},
                    .reference_file => {
                        touch_options.time_to_use = .{ .reference_file = arg.raw };
                        log.debug("got reference file value: '{s}'", .{arg.raw});
                        state = .normal;
                        continue;
                    },
                    .time => {
                        log.debug("got time positional argument, value: '{s}'", .{arg.raw});
                        touch_options.update = parseTimeArgument(arg.raw) orelse {
                            state = .{ .time_argument = arg.raw };
                            break;
                        };
                        state = .normal;
                        continue;
                    },
                    else => break,
                }

                touch_options.first_file_path = arg.raw;
                return touch_options;
            },
        }
    }

    return switch (state) {
        .normal => shared.printInvalidUsage(
            @This(),
            io,
            exe_path,
            "missing file operand",
        ),
        .reference_file => shared.printInvalidUsage(
            @This(),
            io,
            exe_path,
            "expected file path for reference file argument",
        ),
        .time => shared.printInvalidUsage(
            @This(),
            io,
            exe_path,
            "expected WORD string for time argument",
        ),
        .time_argument => |argument| shared.printInvalidUsageAlloc(
            @This(),
            allocator,
            io,
            exe_path,
            "unrecognized value for time option '{s}'",
            .{argument},
        ),
        .invalid_argument => |invalid_arg| switch (invalid_arg) {
            .slice => |slice| shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "unrecognized option '{s}'",
                .{slice},
            ),
            .character => |character| shared.printInvalidUsageAlloc(
                @This(),
                allocator,
                io,
                exe_path,
                "unrecognized option -- '{c}'",
                .{character},
            ),
        },
    };
}

fn parseTimeArgument(argument: []const u8) ?TouchOptions.Update {
    if (std.mem.eql(u8, argument, "access") or
        std.mem.eql(u8, argument, "atime") or
        std.mem.eql(u8, argument, "use"))
    {
        return .access_only;
    }

    if (std.mem.eql(u8, argument, "modify") or
        std.mem.eql(u8, argument, "mtime"))
    {
        return .modification_only;
    }

    return null;
}

fn performTouch(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    options: TouchOptions,
    cwd: std.fs.Dir,
) !void {
    const z = shared.tracy.traceNamed(@src(), "perform touch");
    defer z.end();

    log.debug("performTouch called, options={}", .{options});

    const times = try getTimes(allocator, io, options.time_to_use, cwd);

    log.debug("times to be used for touch: {}", .{times});

    var opt_file_path: ?[]const u8 = options.first_file_path;

    argument_loop: while (opt_file_path) |file_path| : (opt_file_path = args.nextRaw()) {
        const file_zone = shared.tracy.traceNamed(@src(), "process file");
        defer file_zone.end();
        file_zone.addText(file_path);

        const file: std.fs.File = blk: {
            if (std.mem.eql(u8, file_path, "-")) break :blk std.io.getStdOut();

            const file_or_error = switch (options.create) {
                true => cwd.createFile(file_path, .{}),
                false => cwd.openFile(file_path, .{}),
            };

            break :blk file_or_error catch |err| {
                // The file not existing is not an error if create is false.
                if (!options.create and err == error.FileNotFound) continue :argument_loop;

                return shared.printErrorAlloc(
                    @This(),
                    allocator,
                    io,
                    "failed to open '{s}': {s}",
                    .{ file_path, @errorName(err) },
                );
            };
        };
        defer file.close();

        const possible_update_times_error = if (options.update == .both)
            file.updateTimes(times.access_time, times.modification_time)
        else blk: {
            const stat = file.stat() catch |err| {
                return shared.printErrorAlloc(
                    @This(),
                    allocator,
                    io,
                    "failed to stat '{s}': {s}",
                    .{ file_path, @errorName(err) },
                );
            };

            break :blk switch (options.update) {
                .both => unreachable,
                .access_only => file.updateTimes(times.access_time, stat.mtime),
                .modification_only => file.updateTimes(stat.atime, times.modification_time),
            };
        };

        possible_update_times_error catch |err|
            return shared.printErrorAlloc(
            @This(),
            allocator,
            io,
            "failed to update times on '{s}': {s}",
            .{ file_path, @errorName(err) },
        );
    }
}

fn getTimes(
    allocator: std.mem.Allocator,
    io: anytype,
    time_to_use: TouchOptions.TimeToUse,
    cwd: std.fs.Dir,
) !FileTimes {
    switch (time_to_use) {
        .current_time => {
            const time = std.time.nanoTimestamp();
            return .{
                .access_time = time,
                .modification_time = time,
            };
        },
        .reference_file => |reference_file_path| {
            const reference_file = cwd.openFile(reference_file_path, .{}) catch |err| {
                return shared.printErrorAlloc(
                    @This(),
                    allocator,
                    io,
                    "unable to open '{s}': {s}",
                    .{ reference_file_path, @errorName(err) },
                );
            };
            defer reference_file.close();

            const stat = reference_file.stat() catch |err| {
                return shared.printErrorAlloc(
                    @This(),
                    allocator,
                    io,
                    "unable to stat '{s}': {s}",
                    .{ reference_file_path, @errorName(err) },
                );
            };

            return .{
                .access_time = stat.atime,
                .modification_time = stat.mtime,
            };
        },
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

    first_file_path: []const u8 = undefined,

    pub const Update = enum {
        both,
        access_only,
        modification_only,
    };

    pub const TimeToUse = union(enum) {
        current_time,
        reference_file: []const u8,
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
        const create = if (value.create) "true" else "false";
        try writer.writeAll(create);

        try writer.writeAll(", .dereference = ");
        const dereference = if (value.dereference) "true" else "false";
        try writer.writeAll(dereference);

        try writer.writeAll(", .time_to_use = ");
        switch (value.time_to_use) {
            .current_time => try writer.writeAll(".current_time }"),
            inline else => |val| try writer.print(".{{ .{s} = \"{s}\" }} }}", .{ @tagName(value.time_to_use), val }),
        }
    }
};

test "touch - create file" {
    var tmp_dir = try setupTestDirectory();
    defer tmp_dir.cleanup();

    const cwd = tmp_dir.dir;

    // file should not exist
    try std.testing.expectError(
        error.FileNotFound,
        cwd.access("FILE", .{}),
    );

    try subcommands.testExecute(
        @This(),
        &.{"FILE"},
        .{ .cwd = cwd },
    );

    // file should exist
    try cwd.access("FILE", .{});
}

test "touch - don't create file" {
    var tmp_dir = try setupTestDirectory();
    defer tmp_dir.cleanup();

    const cwd = tmp_dir.dir;

    // file should not exist
    try std.testing.expectError(
        error.FileNotFound,
        cwd.access("FILE", .{}),
    );

    try subcommands.testExecute(
        @This(),
        &.{ "-a", "EXISTS" },
        .{ .cwd = cwd },
    );

    // file should still not exist
    try std.testing.expectError(
        error.FileNotFound,
        cwd.access("FILE", .{}),
    );
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

fn setupTestDirectory() !std.testing.TmpDir {
    const tmp_dir = std.testing.tmpDir(.{});
    _ = try tmp_dir.dir.createFile("EXISTS", .{});
    return tmp_dir;
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
