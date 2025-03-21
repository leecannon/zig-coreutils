// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Is this command enabled for the current target?
pub const enabled: bool = true; // USE `shared.target_os` TO DETERMINE IF THE COMMAND IS ENABLED FOR THE CURRENT TARGET

pub const command: Command = .{
    .name = "template", // CHANGE THIS

    .short_help = // CHANGE THIS
    \\Usage: {NAME} [ignored command line arguments]
    \\   or: {NAME} OPTION
    \\
    \\A template command
    \\
    \\  -h         display the short help and exit
    \\  --help     display the full help and exit
    \\  --version  output version information and exit
    \\
    ,

    // ADD `.extended_help` IF EXAMPLES SHOULD BE DISPLAYED

    .execute = impl.execute,
};

// namespace required to prevent tests of disabled commands from being analyzed
const impl = struct {
    fn execute(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        cwd: std.fs.Dir,
        exe_path: []const u8,
    ) Command.Error!void {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = command.name });
        defer z.end();

        _ = cwd;

        const options = try parseArguments(allocator, io, args, exe_path);
        log.debug("options={}", .{options});
    }

    const TemplateOptions = struct {
        pub fn format(
            options: TemplateOptions,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            try writer.writeAll("TemplateOptions{ }");
        }
    };

    fn parseArguments(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        exe_path: []const u8,
    ) !TemplateOptions {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
        defer z.end();

        var opt_arg: ?Arg = try args.nextWithHelpOrVersion(true);

        const options: TemplateOptions = .{};

        const State = union(enum) {
            normal,
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
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = longhand } };
                    break;
                },
                .longhand_with_value => |longhand_with_value| {
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = longhand_with_value.longhand } };
                    break;
                },
                .shorthand => |*shorthand| {
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = shorthand.value } };
                    break;
                },
                .positional => {
                    @branchHint(.cold);
                    std.debug.assert(state == .normal);
                    state = .{ .invalid_argument = .{ .slice = arg.raw } };
                    break;
                },
            }
        }

        return switch (state) {
            .normal => options,
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

    test "template no args" {
        try command.testExecute(&.{}, .{});
    }

    test "template help" {
        try command.testHelp(true);
    }

    test "template version" {
        try command.testVersion();
    }

    test "template fuzz" { // DELETE THIS IF THE COMMAND INTERACTS WITH THE SYSTEM
        try command.testFuzz(.{});
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.template); // CHANGE THIS

const std = @import("std");
const tracy = @import("tracy");
