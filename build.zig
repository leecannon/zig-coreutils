const std = @import("std");
const descriptions = @import("src/descriptions.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const main_exe = b.addExecutable("zig-coreutils", "src/main.zig");
    main_exe.setTarget(target);
    main_exe.setBuildMode(mode);
    main_exe.install();

    const test_step = b.addTest("src/main.zig");
    const run_test_step = b.step("test", "Run the tests");
    run_test_step.dependOn(&test_step.step);
    b.default_step = run_test_step;

    inline for (descriptions.DESCRIPTIONS) |desc| {
        const exe = b.addExecutable(desc.name, "src/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);

        const run_cmd = exe.run();
        //run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run_" ++ desc.name, "Run " ++ desc.name);
        run_step.dependOn(&run_cmd.step);
    }
}
