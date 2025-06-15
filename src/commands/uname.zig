// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Is this command enabled for the current target?
pub const enabled: bool = switch (shared.target_os) {
    .linux, .macos => true,
    .windows => false,
};

pub const command: Command = .{
    .name = "uname",

    .short_help =
    \\Usage: {0s} [OPTION]...
    \\
    \\Print system information. With no OPTION same as -s.
    \\
    \\     -a, --all                print all information, in below order but omits -p and -i if unknown
    \\     -s, --kernel-name        print the kernel name
    \\     -n, --nodename           print the network node hostname
    \\     -r, --kernel-release     print the kernel release
    \\     -v, --kernel-version     print the kernel version
    \\     -m, --machine            print the machine hardware name
    \\     -p, --processor          print the processor type
    \\     -i, --hardware-platform  print the hardware platform
    \\     -o, --operating-system   print the operating system
    \\     -d, --domainname         print the domain name (not supported on all platforms)
    \\     -h, --help               display this help and exit
    \\     --version                output version information and exit
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

        const options = try parseArguments(allocator, io, args, exe_path);
        log.debug("{}", .{options});

        return performUname(allocator, io, system, options);
    }

    fn performUname(
        allocator: std.mem.Allocator,
        io: IO,
        system: System,
        options: UnameOptions,
    ) !void {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "perform uname" });
        defer z.end();

        _ = allocator;

        const uname = system.uname();

        var any_printed = false;

        if (options.kernel_name) {
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.sysname, 0));
            any_printed = true;
        }

        if (options.node_name) {
            if (any_printed) try io.stdoutWriteByte(' ');
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.nodename, 0));
            any_printed = true;
        }

        if (options.kernel_release) {
            if (any_printed) try io.stdoutWriteByte(' ');
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.release, 0));
            any_printed = true;
        }

        if (options.kernel_version) {
            if (any_printed) try io.stdoutWriteByte(' ');
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.version, 0));
            any_printed = true;
        }

        if (options.machine) {
            if (any_printed) try io.stdoutWriteByte(' ');
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.machine, 0));
            any_printed = true;
        }

        switch (options.processor) {
            .always => {
                if (any_printed) try io.stdoutWriteByte(' ');
                try io.stdoutWriteAll("unknown");
                any_printed = true;
            },
            .never, .non_empty => {},
        }

        switch (options.hardware_platform) {
            .always => {
                if (any_printed) try io.stdoutWriteByte(' ');
                try io.stdoutWriteAll("unknown");
                any_printed = true;
            },
            .never, .non_empty => {},
        }

        if (options.os) {
            if (any_printed) try io.stdoutWriteByte(' ');
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.sysname, 0));
            any_printed = true;
        }

        if (target_has_domainname and options.domainname) {
            if (any_printed) try io.stdoutWriteByte(' ');
            try io.stdoutWriteAll(std.mem.sliceTo(&uname.domainname, 0));
            any_printed = true;
        }

        try io.stdoutWriteByte('\n');
    }

    const target_has_domainname = switch (shared.target_os) {
        .linux => true,
        .macos => false,
        .windows => false,
    };

    const UnameOptions = struct {
        kernel_name: bool = true,
        node_name: bool = false,
        kernel_release: bool = false,
        kernel_version: bool = false,
        machine: bool = false,
        processor: Show = .never,
        hardware_platform: Show = .never,
        os: bool = false,
        domainname: bool = false,

        const Show = enum {
            never,
            always,
            non_empty,
        };

        pub fn format(
            options: UnameOptions,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.writeAll("UnameOptions {");

            try writer.writeAll(comptime "\n" ++ shared.option_log_indentation ++ ".kernel_name = .");
            try writer.writeAll(if (options.kernel_name) "true" else "false");

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".node_name = .");
            try writer.writeAll(if (options.node_name) "true" else "false");

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".kernel_release = .");
            try writer.writeAll(if (options.kernel_release) "true" else "false");

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".kernel_version = .");
            try writer.writeAll(if (options.kernel_version) "true" else "false");

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".machine = .");
            try writer.writeAll(if (options.machine) "true" else "false");

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".processor = .");
            try writer.writeAll(@tagName(options.processor));

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".hardware_platform = .");
            try writer.writeAll(@tagName(options.hardware_platform));

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".os = .");
            try writer.writeAll(if (options.os) "true" else "false");

            try writer.writeAll(comptime ",\n" ++ shared.option_log_indentation ++ ".domainname = .");
            try writer.writeAll(if (options.domainname) "true" else "false");

            try writer.writeAll(",\n}");
        }
    };

    fn parseArguments(
        allocator: std.mem.Allocator,
        io: IO,
        args: *Arg.Iterator,
        exe_path: []const u8,
    ) !UnameOptions {
        const z: tracy.Zone = .begin(.{ .src = @src(), .name = "parse arguments" });
        defer z.end();

        var opt_arg: ?Arg = try args.nextWithHelpOrVersion(true);

        var options: UnameOptions = .{};

        const State = union(enum) {
            normal,
            domainname_on_unsupported,
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
                    std.debug.assert(state == .normal);

                    if (std.mem.eql(u8, longhand, "all")) {
                        options.kernel_name = true;
                        options.node_name = true;
                        options.kernel_release = true;
                        options.kernel_version = true;
                        options.machine = true;
                        if (options.processor == .never) options.processor = .non_empty;
                        if (options.hardware_platform == .never) options.hardware_platform = .non_empty;
                        options.os = true;
                        options.domainname = true;
                        log.debug("got all longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "kernel-name")) {
                        options.kernel_name = true;
                        log.debug("got kernel name longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "nodename")) {
                        options.node_name = true;
                        log.debug("got node name longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "kernel-release")) {
                        options.kernel_release = true;
                        log.debug("got kernel release longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "kernel-version")) {
                        options.kernel_version = true;
                        log.debug("got kernel version longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "machine")) {
                        options.machine = true;
                        log.debug("got machine longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "processor")) {
                        options.processor = .always;
                        log.debug("got processor longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "hardware-platform")) {
                        options.hardware_platform = .always;
                        log.debug("got hardware platform longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "operating-system")) {
                        options.os = true;
                        log.debug("got operating system longhand", .{});
                    } else if (std.mem.eql(u8, longhand, "domainname")) {
                        if (!target_has_domainname) {
                            @branchHint(.cold);
                            state = .domainname_on_unsupported;
                            break :outer;
                        }

                        options.domainname = true;
                        log.debug("got domainname longhand", .{});
                    } else {
                        @branchHint(.cold);
                        state = .{ .invalid_argument = .{ .slice = longhand } };
                        break :outer;
                    }
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
                        switch (char) {
                            'a' => {
                                options.kernel_name = true;
                                options.node_name = true;
                                options.kernel_release = true;
                                options.kernel_version = true;
                                options.machine = true;
                                if (options.processor == .never) options.processor = .non_empty;
                                if (options.hardware_platform == .never) options.hardware_platform = .non_empty;
                                options.os = true;
                                options.domainname = true;
                                log.debug("got all shorthand", .{});
                            },
                            's' => {
                                options.kernel_name = true;
                                log.debug("got kernel name shorthand", .{});
                            },
                            'n' => {
                                options.node_name = true;
                                log.debug("got node name shorthand", .{});
                            },
                            'r' => {
                                options.kernel_release = true;
                                log.debug("got kernel release shorthand", .{});
                            },
                            'v' => {
                                options.kernel_version = true;
                                log.debug("got kernel version shorthand", .{});
                            },
                            'm' => {
                                options.machine = true;
                                log.debug("got machine shorthand", .{});
                            },
                            'p' => {
                                options.processor = .always;
                                log.debug("got processor shorthand", .{});
                            },
                            'i' => {
                                options.hardware_platform = .always;
                                log.debug("got hardware platform shorthand", .{});
                            },
                            'o' => {
                                options.os = true;
                                log.debug("gotoperating system shorthand", .{});
                            },
                            'd' => {
                                if (!target_has_domainname) {
                                    @branchHint(.cold);
                                    state = .domainname_on_unsupported;
                                    break :outer;
                                }

                                options.domainname = true;
                                log.debug("got domainname shorthand", .{});
                            },
                            else => {
                                @branchHint(.cold);
                                state = .{ .invalid_argument = .{ .character = char } };
                                break :outer;
                            },
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
            .normal => options,
            .domainname_on_unsupported => command.printInvalidUsage(
                io,
                exe_path,
                "domainname is not supported on this platform",
            ),
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

    test "uname help" {
        try command.testHelp(true);
    }

    test "uname version" {
        try command.testVersion();
    }

    test "uname" {
        var stdout = std.ArrayList(u8).init(std.testing.allocator);
        defer stdout.deinit();

        try command.testExecute(&.{"-a"}, .{
            .stdout = stdout.writer().any(),
            .system_description = .{
                .uname = .{
                    .sysname = "sysname",
                    .nodename = "nodename",
                    .release = "release",
                    .version = "version",
                    .machine = "machine",
                    .domainname = "domainname",
                },
            },
        });

        const expected = if (target_has_domainname)
            "sysname nodename release version machine sysname domainname\n"
        else
            "sysname nodename release version machine sysname\n";

        try std.testing.expectEqualStrings(expected, stdout.items);
    }
};

const Arg = @import("../Arg.zig");
const Command = @import("../Command.zig");
const IO = @import("../IO.zig");
const shared = @import("../shared.zig");
const System = @import("../system/System.zig");

const log = std.log.scoped(.uname);

const std = @import("std");
const tracy = @import("tracy");
