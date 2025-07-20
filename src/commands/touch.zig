// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const enabled: bool = true;

pub const command: Command = .{
    .name = "touch",

    .short_help =
    \\Usage: {NAME} [OPTION]... FILE...
    \\
    \\Update the access and modification times of each FILE to the current time.
    \\
    \\A FILE argument that does not exist is created empty, unless -c or -h is supplied.
    \\
    \\Mandatory arguments to long options are mandatory for short options too.
    \\  -a                    change only the access time
    \\  -c, --no-create       do not create any files
    \\  -f                    (ignored)
    \\  -m                    change only the modification time
    \\  -r, --reference=FILE  use this file's times instead of the current time
    \\  --time=WORD           change the specified time:
    \\                          WORD is access, atime, or use: equivalent to -a
    \\                          WORD is modify or mtime: equivalent to -m
    \\  --help                display the help and exit
    \\  --version             output version information and exit
    \\
    ,

    // TODO: support `-h, --no-dereference  affect symbolic link instead of any referenced file`

    .extended_help =
    \\Examples:
    \\  touch FILE
    \\  touch -c FILE
    \\  touch -r REFFILE FILE
    \\  touch -a FILE
    \\
    ,

    .execute = impl.execute,
};

// namespace required to prevent tests of disabled commands from being analyzed
const impl = struct {
    fn execute(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        system: System,
        exe_path: []const u8,
    ) Command.Error!void {
        const options = try parseArguments(allocator, io, args, exe_path);
        log.debug("{f}", .{options});

        return performTouch(allocator, io, args, options, system);
    }

    fn performTouch(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        options: TouchOptions,
        system: System,
    ) !void {
        const cwd = system.cwd();

        const times = try getTimes(allocator, io, options.time_to_use, cwd);
        log.debug("times to be used for touch: {}", .{times});

        var opt_file_path: ?[]const u8 = options.first_file_path;

        argument_loop: while (opt_file_path) |file_path| : (opt_file_path = args.nextRaw()) {
            const file: System.File = blk: {
                const file_or_error = switch (options.create) {
                    true => cwd.createFile(file_path, .{ .truncate = false }),
                    false => cwd.openFile(file_path, .{}),
                };

                break :blk file_or_error catch |err| {
                    // The file not existing is not an error if create is false.
                    if (!options.create and err == error.FileNotFound) continue :argument_loop;

                    return command.printErrorAlloc(
                        allocator,
                        io,
                        "failed to open '{s}': {t}",
                        .{ file_path, err },
                    );
                };
            };
            defer file.close();

            const possible_update_times_error = if (options.update == .both)
                file.updateTimes(times.access_time, times.modification_time)
            else blk: {
                const stat = file.stat() catch |err|
                    return command.printErrorAlloc(
                        allocator,
                        io,
                        "failed to stat '{s}': {t}",
                        .{ file_path, err },
                    );

                break :blk switch (options.update) {
                    .both => unreachable,
                    .access_only => file.updateTimes(times.access_time, stat.mtime),
                    .modification_only => file.updateTimes(stat.atime, times.modification_time),
                };
            };

            possible_update_times_error catch |err|
                return command.printErrorAlloc(
                    allocator,
                    io,
                    "failed to update times on '{s}': {t}",
                    .{ file_path, err },
                );
        }
    }

    fn getTimes(
        allocator: std.mem.Allocator,
        io: IO,
        time_to_use: TouchOptions.TimeToUse,
        cwd: System.Dir,
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
                const reference_file = cwd.openFile(reference_file_path, .{}) catch |err|
                    return command.printErrorAlloc(
                        allocator,
                        io,
                        "unable to open '{s}': {t}",
                        .{ reference_file_path, err },
                    );
                defer reference_file.close();

                const stat = reference_file.stat() catch |err|
                    return command.printErrorAlloc(
                        allocator,
                        io,
                        "unable to stat '{s}': {t}",
                        .{ reference_file_path, err },
                    );

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

        pub fn format(options: TouchOptions, writer: *std.Io.Writer) !void {
            try writer.writeAll("TouchOptions {");

            try writer.writeAll(comptime "\n" ++ shared.option_log_indentation ++ ".update = .");
            try writer.writeAll(@tagName(options.update));

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".create = ");
            const create = if (options.create) "true" else "false";
            try writer.writeAll(create);

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".time_to_use = ");

            switch (options.time_to_use) {
                .current_time => try writer.writeAll(".current_time"),
                inline else => |val| try writer.print(
                    ".{{ .{t} = \"{s}\" }}",
                    .{ options.time_to_use, val },
                ),
            }

            try writer.writeAll(",\n}");
        }
    };

    fn parseArguments(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        exe_path: []const u8,
    ) !TouchOptions {
        // `-h` not supported to allow for future no dereference shorthand
        var opt_arg: ?Arg = try args.nextWithHelpOrVersion(false);

        var touch_options: TouchOptions = .{};

        const State = union(enum) {
            normal,
            reference_file,
            time,

            invalid_time_argument: []const u8,
            invalid_argument: Argument,

            const Argument = union(enum) {
                slice: []const u8,
                character: u8,
            };
        };

        var state: State = .normal;

        outer: while (opt_arg) |*arg| : (opt_arg = args.next()) {
            switch (arg.arg_type) {
                .longhand => |longhand| {
                    if (state != .normal) {
                        @branchHint(.cold);
                        break :outer;
                    }

                    if (std.mem.eql(u8, longhand, "no-create")) {
                        touch_options.create = false;
                        log.debug("got do not create file longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "reference-file")) {
                        state = .reference_file;
                        log.debug("got reference file longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "time")) {
                        state = .time;
                        log.debug("got time longhand", .{});
                    } else {
                        @branchHint(.cold);
                        state = .{ .invalid_argument = .{ .slice = longhand } };
                        break :outer;
                    }
                },
                .shorthand => |*shorthand| {
                    if (state != .normal) {
                        @branchHint(.cold);
                        break :outer;
                    }

                    while (shorthand.next()) |char| {
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
                                @branchHint(.cold);
                                state = .{ .invalid_argument = .{ .character = char } };
                                break :outer;
                            },
                        }
                    }
                },
                .longhand_with_value => |longhand_with_value| {
                    if (state != .normal) {
                        @branchHint(.cold);
                        break :outer;
                    }

                    if (std.mem.eql(u8, longhand_with_value.longhand, "reference")) {
                        touch_options.time_to_use = .{ .reference_file = longhand_with_value.value };
                        log.debug(
                            "got reference file longhand, reference file: '{s}'",
                            .{longhand_with_value.value},
                        );
                    } else if (std.mem.eql(u8, longhand_with_value.longhand, "time")) {
                        log.debug("got time longhand, value: '{s}'", .{longhand_with_value.value});
                        touch_options.update = parseTimeArgument(longhand_with_value.value) orelse {
                            @branchHint(.cold);
                            state = .{ .invalid_time_argument = longhand_with_value.value };
                            break :outer;
                        };
                    } else {
                        @branchHint(.cold);
                        state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                        break :outer;
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
                                @branchHint(.cold);
                                state = .{ .invalid_time_argument = arg.raw };
                                break :outer;
                            };
                            state = .normal;
                            continue;
                        },
                        else => {
                            @branchHint(.cold);
                            break :outer;
                        },
                    }

                    touch_options.first_file_path = arg.raw;
                    return touch_options;
                },
            }
        }

        return switch (state) {
            .normal => command.printInvalidUsage(
                io,
                exe_path,
                "missing file operand",
            ),
            .reference_file => command.printInvalidUsage(
                io,
                exe_path,
                "expected file path for reference file argument",
            ),
            .time => command.printInvalidUsage(
                io,
                exe_path,
                "expected WORD string for time argument",
            ),
            .invalid_time_argument => |argument| command.printInvalidUsageAlloc(
                allocator,
                io,
                exe_path,
                "unrecognized value for time option '{s}'",
                .{argument},
            ),
            .invalid_argument => |invalid_arg| switch (invalid_arg) {
                .slice => |slice| command.printInvalidUsageAlloc(
                    allocator,
                    io,
                    exe_path,
                    "unrecognized option '{s}'",
                    .{slice},
                ),
                .character => |character| command.printInvalidUsageAlloc(
                    allocator,
                    io,
                    exe_path,
                    "unrecognized short option: '{c}'",
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

    test "touch no args" {
        try command.testError(
            &.{},
            .{},
            "missing file operand",
        );
    }

    test "touch help" {
        try command.testHelp(false);
    }

    test "touch version" {
        try command.testVersion();
    }

    test "touch fuzz" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        // build a simple fs tree
        const dir1 = try fs_description.root.addDirectory("dir1");
        _ = try dir1.addFile("file1", "touch fuzz");
        _ = try dir1.addDirectory("dir2");
        fs_description.setCwd(dir1);

        try command.testFuzz(.{
            .system_description = .{ .file_system = fs_description },
            .expect_stdout_output_on_success = false,
            .corpus = &.{
                "touch file",
                "touch dir1/file1",
                "touch -c file1",
            },
        });
    }

    test "touch simple" {
        const fs_description = try System.TestBackend.Description.FileSystemDescription.create(
            std.testing.allocator,
        );
        defer fs_description.destroy();

        var system: System = undefined;
        defer system._backend.destroy();

        try command.testExecute(
            &.{"created"},
            .{
                .system_description = .{ .file_system = fs_description },
                .test_backend_behaviour = .{ .provide = &system },
            },
        );

        const created_file = try system.cwd().openFile("created", .{});
        defer created_file.close();

        try shared.customExpectEqual((try created_file.stat()).size, 0);
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.touch);

const std = @import("std");
