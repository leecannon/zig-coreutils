const supported_oses: []const std.Target.Os.Tag = &.{
    .linux,
    .macos,
    .windows,
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const trace = b.option(bool, "trace", "enable tracy tracing") orelse false;

    const coverage = b.option(
        bool,
        "coverage",
        "Generate test coverage for the native test target with kcov",
    ) orelse false;

    const options = b.addOptions();
    options.addOption(
        []const u8,
        "version",
        try getVersionString(b, coreutils_version, b.build_root.path.?),
    );
    options.addOption(bool, "trace", trace);
    const options_module = options.createModule();

    // exe
    {
        const target = b.standardTargetOptions(.{});

        if (std.mem.indexOfScalar(std.Target.Os.Tag, supported_oses, target.result.os.tag) == null) {
            std.debug.panic("unsupported target OS {s}", .{@tagName(target.result.os.tag)});
        }

        const coreutils_exe = b.addExecutable(.{
            .name = "zig-coreutils",
            .root_module = createRootModule(
                b,
                target,
                optimize,
                trace,
                options_module,
            ),
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

    const run_non_native_tests = b.option(
        bool,
        "run_non_native_tests",
        "run non-native tests",
    ) orelse false;

    if (run_non_native_tests) {
        b.enable_wine = true;
        b.enable_darling = false; // FIXME: for some reason this never finishes
    }

    // test and check
    {
        const check_step = b.step("check", "");
        const test_step = b.step("test", "Run the tests for all targets");

        for (supported_oses) |os_tag| {
            const target = b.resolveTargetQuery(.{ .os_tag = os_tag });
            const is_native_target = target.result.os.tag == builtin.os.tag;

            try createTestAndCheckSteps(
                b,
                target,
                optimize,
                trace,
                options_module,
                is_native_target,
                coverage,
                test_step,
                check_step,
                run_non_native_tests,
            );
        }
    }
}

fn createRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    trace: bool,
    options_module: *std.Build.Module,
) *std.Build.Module {
    const tracy_dep = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });

    const coreutils_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    coreutils_module.addImport("options", options_module);
    coreutils_module.addImport("tracy", tracy_dep.module("tracy"));

    if (trace) {
        coreutils_module.addImport("tracy_impl", tracy_dep.module("tracy_impl_enabled"));
    } else {
        coreutils_module.addImport("tracy_impl", tracy_dep.module("tracy_impl_disabled"));
    }

    return coreutils_module;
}

fn createTestAndCheckSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    trace: bool,
    options_module: *std.Build.Module,
    is_native_target: bool,
    coverage: bool,
    test_step: *std.Build.Step,
    check_step: *std.Build.Step,
    run_non_native_tests: bool,
) !void {
    const module = createRootModule(
        b,
        target,
        optimize,
        trace,
        options_module,
    );

    const coreutils_test = b.addTest(.{
        .name = b.fmt("test_zig-coreutils-{s}", .{@tagName(target.result.os.tag)}),
        .root_module = module,
    });

    if (is_native_target) {
        if (coverage) {
            coreutils_test.setExecCmd(&[_]?[]const u8{
                "kcov",
                b.fmt("--include-path={s}", .{
                    try b.build_root.join(b.allocator, &.{"src"}),
                }),
                b.fmt("--exclude-path={s}", .{
                    try b.build_root.join(b.allocator, &.{ "src", "main.zig" }),
                }),
                b.pathJoin(&.{ b.install_prefix, "kcov" }),
                null,
            });
        }
    }

    const target_test_step = b.step(
        b.fmt("test_{s}", .{@tagName(target.result.os.tag)}),
        b.fmt("Run the tests for {s}", .{@tagName(target.result.os.tag)}),
    );

    if (is_native_target or run_non_native_tests) {
        const run_coreutils_test = b.addRunArtifact(coreutils_test);

        if (!is_native_target) {
            // FIXME: why do we need to change both of these?
            run_coreutils_test.skip_foreign_checks = true;
            run_coreutils_test.failing_to_execute_foreign_is_an_error = false;
        }

        target_test_step.dependOn(&run_coreutils_test.step);
    } else {
        target_test_step.dependOn(&coreutils_test.step);
    }

    const build_exe = b.addExecutable(.{
        .name = b.fmt("build_zig-coreutils-{s}", .{@tagName(target.result.os.tag)}),
        .root_module = module,
    });
    target_test_step.dependOn(&build_exe.step);

    test_step.dependOn(target_test_step);

    {
        const coreutils_exe_check = b.addExecutable(.{
            .name = b.fmt("check_zig-coreutils-{s}", .{@tagName(target.result.os.tag)}),
            .root_module = createRootModule(
                b,
                target,
                optimize,
                trace,
                options_module,
            ),
        });
        const coreutils_test_check = b.addTest(.{
            .name = b.fmt("check_test_zig-coreutils-{s}", .{@tagName(target.result.os.tag)}),
            .root_module = createRootModule(
                b,
                target,
                optimize,
                trace,
                options_module,
            ),
        });

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
