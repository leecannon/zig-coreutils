const std = @import("std");
const deps = @import("deps.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const main_exe = b.addExecutable("zig-coreutils", "src/main.zig");
    main_exe.single_threaded = true;
    deps.addAllTo(main_exe);

    if (mode != .Debug) {
        main_exe.link_function_sections = true;
        main_exe.want_lto = true;
    }

    main_exe.setTarget(target);
    main_exe.setBuildMode(mode);
    main_exe.install();

    const test_step = b.addTest("src/main.zig");
    deps.addAllTo(test_step);
    const run_test_step = b.step("test", "Run the tests");
    run_test_step.dependOn(&test_step.step);
    b.default_step = run_test_step;
}
