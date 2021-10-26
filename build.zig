const std = @import("std");
const deps = @import("deps.zig");
const SUBCOMMANDS = @import("src/subcommands.zig").SUBCOMMANDS;

const coreutils_version = std.builtin.Version{ .major = 0, .minor = 0, .patch = 1 };

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const options = b.addOptions();
    const version = v: {
        const version_string = b.fmt(
            "{d}.{d}.{d}",
            .{ coreutils_version.major, coreutils_version.minor, coreutils_version.patch },
        );

        var code: u8 = undefined;
        const git_describe_untrimmed = b.execAllowFail(&[_][]const u8{
            "git", "-C", b.build_root, "describe", "--match", "*.*.*", "--tags",
        }, &code, .Ignore) catch {
            break :v version_string;
        };
        const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

        switch (std.mem.count(u8, git_describe, "-")) {
            0 => {
                // Tagged release version (e.g. 0.8.0).
                if (!std.mem.eql(u8, git_describe, version_string)) {
                    std.debug.print(
                        "Zig-Coreutils version '{s}' does not match Git tag '{s}'\n",
                        .{ version_string, git_describe },
                    );
                    std.process.exit(1);
                }
                break :v version_string;
            },
            2 => {
                // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
                var it = std.mem.split(u8, git_describe, "-");
                const tagged_ancestor = it.next() orelse unreachable;
                const commit_height = it.next() orelse unreachable;
                const commit_id = it.next() orelse unreachable;

                const ancestor_ver = try std.builtin.Version.parse(tagged_ancestor);
                if (coreutils_version.order(ancestor_ver) != .gt) {
                    std.debug.print(
                        "Zig-Coreutils version '{}' must be greater than tagged ancestor '{}'\n",
                        .{ coreutils_version, ancestor_ver },
                    );
                    std.process.exit(1);
                }

                // Check that the commit hash is prefixed with a 'g' (a Git convention).
                if (commit_id.len < 1 or commit_id[0] != 'g') {
                    std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                    break :v version_string;
                }

                // The version is reformatted in accordance with the https://semver.org specification.
                break :v b.fmt("{s}-dev.{s}+{s}", .{ version_string, commit_height, commit_id[1..] });
            },
            else => {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                break :v version_string;
            },
        }
    };
    options.addOption([:0]const u8, "version", try b.allocator.dupeZ(u8, version));

    const main_exe = b.addExecutable("zig-coreutils", "src/main.zig");
    main_exe.single_threaded = true;
    main_exe.addOptions("options", options);
    deps.pkgs.addAllTo(main_exe);

    if (mode != .Debug) {
        main_exe.link_function_sections = true;
        main_exe.want_lto = true;
    }

    main_exe.setTarget(target);
    main_exe.setBuildMode(mode);
    main_exe.install();

    const test_step = b.addTest("src/main.zig");
    test_step.addOptions("options", options);
    deps.pkgs.addAllTo(test_step);
    const run_test_step = b.step("test", "Run the tests");
    run_test_step.dependOn(&test_step.step);
    b.default_step = run_test_step;

    inline for (SUBCOMMANDS) |subcommand| {
        const run_subcommand = b.addExecutable(subcommand.name, "src/main.zig");
        run_subcommand.addOptions("options", options);

        run_subcommand.single_threaded = true;
        deps.pkgs.addAllTo(run_subcommand);
        if (mode != .Debug) {
            run_subcommand.link_function_sections = true;
            run_subcommand.want_lto = true;
        }
        run_subcommand.setTarget(target);
        run_subcommand.setBuildMode(mode);

        const run_cmd = run_subcommand.run();
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(subcommand.name, "Run '" ++ subcommand.name ++ "'");
        run_step.dependOn(&run_cmd.step);
    }
}
