const std = @import("std");
const deps = @import("deps.zig");
const SUBCOMMANDS = @import("src/subcommands.zig").SUBCOMMANDS;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const main_exe = b.addExecutable("zig-coreutils", "src/main.zig");
    main_exe.single_threaded = true;
    deps.pkgs.addAllTo(main_exe);

    if (mode != .Debug) {
        main_exe.link_function_sections = true;
        main_exe.want_lto = true;
    }

    main_exe.setTarget(target);
    main_exe.setBuildMode(mode);
    main_exe.install();

    const test_step = b.addTest("src/main.zig");
    deps.pkgs.addAllTo(test_step);
    const run_test_step = b.step("test", "Run the tests");
    run_test_step.dependOn(&test_step.step);
    b.default_step = run_test_step;

    inline for (SUBCOMMANDS) |subcommand| {
        const run_subcommand = b.addExecutable(subcommand.name, "src/main.zig");
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
