// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const enabled: bool = true;

pub const command: Command = .{
    .name = "clear",

    .short_help =
    \\Usage: {NAME} [OPTION]
    \\
    \\Clear the screen.
    \\
    \\  -x         don't clear the scrollback
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
    ,

    .extended_help =
    \\Examples:
    \\  clear
    \\  clear -x
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
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = command.name });
        defer z.end();

        _ = system;

        const options = try parseArguments(allocator, io, args, exe_path);
        log.debug("{}", .{options});

        try io.stdoutWriteAll(
            if (options.clear_scrollback)
                "\x1b[H\x1b[2J\x1b[3J"
            else
                "\x1b[H\x1b[2J",
        );
    }

    const ClearOptions = struct {
        clear_scrollback: bool = true,

        pub fn format(
            options: ClearOptions,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.writeAll("ClearOptions {");
            try writer.writeAll(comptime "\n" ++ shared.option_log_indentation ++ ".clear_scrollback = .");
            try writer.writeAll(if (options.clear_scrollback) "true" else "false");
            try writer.writeAll(",\n}");
        }
    };

    fn parseArguments(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        exe_path: []const u8,
    ) !ClearOptions {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
        defer z.end();

        var opt_arg: ?Arg = try args.nextWithHelpOrVersion(true);

        var clear_options: ClearOptions = .{};

        const State = union(enum) {
            normal,
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
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = longhand } };
                    break :outer;
                },
                .longhand_with_value => |longhand_with_value| {
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                    break :outer;
                },
                .shorthand => |*shorthand| {
                    std.debug.assert(state == .normal);

                    while (shorthand.next()) |char| {
                        if (char == 'x') {
                            clear_options.clear_scrollback = false;
                            log.debug("got dont clear scrollback option", .{});
                        } else {
                            @branchHint(.cold);
                            state = .{ .invalid_argument = .{ .character = char } };
                            break :outer;
                        }
                    }
                },
                .positional => {
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = arg.raw } };
                    break :outer;
                },
            }
        }

        return switch (state) {
            .normal => clear_options,
            .invalid_argument => |invalid_arg| switch (invalid_arg) {
                .slice => |slice| command.printInvalidUsageAlloc(
                    allocator,
                    io,
                    exe_path,
                    "unrecognized option: '{s}'",
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

    test "clear no args" {
        var stdout = std.ArrayList(u8).init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(
            &.{},
            .{ .stdout = stdout.writer().any() },
        );

        try std.testing.expectEqualStrings("\x1b[H\x1b[2J\x1b[3J", stdout.items);
    }

    test "clear - don't clear scrollback" {
        var stdout = std.ArrayList(u8).init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(
            &.{"-x"},
            .{ .stdout = stdout.writer().any() },
        );

        try std.testing.expectEqualStrings("\x1b[H\x1b[2J", stdout.items);
    }

    test "clear help" {
        try command.testHelp(true);
    }

    test "clear version" {
        try command.testVersion();
    }

    test "clear fuzz" {
        try command.testFuzz(.{
            .expect_stdout_output_on_success = true,
        });
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.clear);

const std = @import("std");
const tracy = @import("tracy");
