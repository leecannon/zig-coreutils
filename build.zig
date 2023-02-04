const std = @import("std");
const SUBCOMMANDS = @import("src/subcommands.zig").SUBCOMMANDS;

const coreutils_version = std.builtin.Version{ .major = 0, .minor = 0, .patch = 7 };

pub fn build(b: *std.Build) !void {
    b.prominent_compile_errors = true;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (!target.isLinux()) {
        std.debug.print("Currently only linux is supported\n", .{});
        return error.UnsupportedOperatingSystem;
    }

    const coverage = b.option(bool, "coverage", "Generate test coverage data with kcov") orelse false;
    const coverage_output_dir = b.option([]const u8, "coverage_output_dir", "Output directory for coverage data") orelse
        b.pathJoin(&.{ b.install_prefix, "kcov" });

    const trace = b.option(bool, "trace", "enable tracy tracing") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "trace", trace);

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

    const exe = b.addExecutable(.{
        .name = "zig-coreutils",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    if (optimize != .Debug) {
        exe.link_function_sections = true;
        exe.want_lto = true;
    }

    exe.install();

    exe.addOptions("options", options);
    exe.addPackagePath("zsw", "zsw/src/main.zig");

    if (trace) {
        includeTracy(exe);
    }

    const run_cmd = exe.run();
    run_cmd.expected_exit_code = null;
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.addTest(.{ .root_source_file = .{ .path = "src/main.zig" } });
    test_step.addOptions("options", options);
    test_step.addPackagePath("zsw", "zsw/src/main.zig");
    if (trace) {
        includeTracy(test_step);
    }

    if (coverage) {
        const src_dir = b.pathJoin(&.{ b.build_root, "src" });
        const include_pattern = b.fmt("--include-pattern={s}", .{src_dir});

        test_step.setExecCmd(&[_]?[]const u8{
            "kcov",
            include_pattern,
            coverage_output_dir,
            null,
        });
    }

    const run_test_step = b.step("test", "Run the tests");
    run_test_step.dependOn(&test_step.step);
    // as this is set as the default step also get it to trigger an install of the main exe
    test_step.step.dependOn(b.getInstallStep());
}

fn includeTracy(exe: *std.Build.LibExeObjStep) void {
    exe.linkLibC();
    exe.linkLibCpp();
    exe.addIncludePath("tracy/public");

    const tracy_c_flags: []const []const u8 = if (exe.target.isWindows() and exe.target.getAbi() == .gnu)
        &.{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
    else
        &.{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

    exe.addCSourceFile("tracy/public/TracyClient.cpp", tracy_c_flags);

    if (exe.target.isWindows()) {
        exe.linkSystemLibrary("Advapi32");
        exe.linkSystemLibrary("User32");
        exe.linkSystemLibrary("Ws2_32");
        exe.linkSystemLibrary("DbgHelp");
    }
}
