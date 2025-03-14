pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracy_dep = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });

    const coreutils_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const trace = b.option(bool, "trace", "enable tracy tracing") orelse false;

    const options = b.addOptions();
    options.addOption(
        []const u8,
        "version",
        try getVersionString(b, coreutils_version, b.build_root.path.?),
    );
    options.addOption(bool, "trace", trace);
    coreutils_module.addImport("options", options.createModule());
    coreutils_module.addImport("tracy", tracy_dep.module("tracy"));

    if (trace) {
        coreutils_module.addImport("tracy_impl", tracy_dep.module("tracy_impl_enabled"));
    } else {
        coreutils_module.addImport("tracy_impl", tracy_dep.module("tracy_impl_disabled"));
    }

    // exe
    {
        const coreutils_exe = b.addExecutable(.{
            .name = "coreutils",
            .root_module = coreutils_module,
        });
        b.installArtifact(coreutils_exe);

        const run_coreutils_exe = b.addRunArtifact(coreutils_exe);
        run_coreutils_exe.step.dependOn(b.getInstallStep());
        run_coreutils_exe.stdio = .inherit;
        if (b.args) |args| {
            run_coreutils_exe.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_coreutils_exe.step);
    }

    // test
    {
        const coreutils_test = b.addTest(.{
            .root_module = coreutils_module,
            .target = target,
            .optimize = optimize,
        });

        const coverage = b.option(
            bool,
            "coverage",
            "Generate test coverage with kcov",
        ) orelse false;

        if (coverage) {
            coreutils_test.setExecCmd(&[_]?[]const u8{
                "kcov",
                b.fmt("--include-pattern={s}", .{try b.build_root.join(b.allocator, &.{"src"})}),
                b.pathJoin(&.{ b.install_prefix, "kcov" }),
                null,
            });
        }

        const run_coreutils_test = b.addRunArtifact(coreutils_test);

        const test_step = b.step("test", "Run the tests");
        test_step.dependOn(&run_coreutils_test.step);
    }

    // check
    {
        const coreutils_exe_check = b.addExecutable(.{
            .name = "check_coreutils",
            .root_module = coreutils_module,
        });
        const coreutils_test_check = b.addTest(.{
            .root_module = coreutils_module,
        });

        const check_step = b.step("check", "");
        check_step.dependOn(&coreutils_exe_check.step);
        check_step.dependOn(&coreutils_test_check.step);
    }
}

/// Gets the version string.
fn getVersionString(b: *std.Build, base_semantic_version: std.SemanticVersion, root_path: []const u8) ![]const u8 {
    const version_string = b.fmt(
        "{d}.{d}.{d}",
        .{ base_semantic_version.major, base_semantic_version.minor, base_semantic_version.patch },
    );

    var exit_code: u8 = undefined;
    const raw_git_describe_output = b.runAllowFail(&[_][]const u8{
        "git", "-C", root_path, "--git-dir", ".git", "describe", "--match", "*.*.*", "--tags", "--abbrev=9",
    }, &exit_code, .Ignore) catch {
        return b.fmt("{s}-unknown", .{version_string});
    };
    const git_describe_output = std.mem.trim(u8, raw_git_describe_output, " \n\r");

    switch (std.mem.count(u8, git_describe_output, "-")) {
        0 => {
            // Tagged release version (e.g. 0.8.0).
            if (!std.mem.eql(u8, git_describe_output, version_string)) {
                std.debug.print(
                    "version '{s}' does not match Git tag '{s}'\n",
                    .{ version_string, git_describe_output },
                );
                std.process.exit(1);
            }
            return version_string;
        },
        2 => {
            // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
            var hash_iterator = std.mem.splitScalar(u8, git_describe_output, '-');
            const tagged_ancestor_version_string = hash_iterator.next() orelse unreachable;
            const commit_height = hash_iterator.next() orelse unreachable;
            const commit_id = hash_iterator.next() orelse unreachable;

            const ancestor_version = try std.SemanticVersion.parse(tagged_ancestor_version_string);
            if (base_semantic_version.order(ancestor_version) != .gt) {
                std.debug.print(
                    "version '{}' must be greater than tagged ancestor '{}'\n",
                    .{ base_semantic_version, ancestor_version },
                );
                std.process.exit(1);
            }

            // Check that the commit hash is prefixed with a 'g' (a Git convention).
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.print("unexpected `git describe` output: {s}\n", .{git_describe_output});
                return version_string;
            }

            // The version is reformatted in accordance with the https://semver.org specification.
            return b.fmt("{s}-dev.{s}+{s}", .{ version_string, commit_height, commit_id[1..] });
        },
        else => {
            std.debug.print("unexpected `git describe` output: {s}\n", .{git_describe_output});
            return version_string;
        },
    }
}

comptime {
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(build_zig_zon.minimum_zig_version) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint(
            "Your Zig version {} does not meet the minimum build requirement of {}",
            .{ current_zig, min_zig },
        ));
    }
}

const coreutils_version = std.SemanticVersion.parse(build_zig_zon.version) catch unreachable;

const build_zig_zon: BuildZigZon = @import("build.zig.zon");

// requirement to have a type will be removed by https://github.com/ziglang/zig/pull/22907
const BuildZigZon = struct {
    name: @TypeOf(.enum_literal),
    version: []const u8,
    minimum_zig_version: []const u8,
    dependencies: Deps,
    paths: []const []const u8,
    fingerprint: u64,

    pub const Deps = struct {
        tracy: UrlDep,

        const UrlDep = struct {
            url: []const u8,
            hash: []const u8,
        };
    };
};

const std = @import("std");
const builtin = @import("builtin");
