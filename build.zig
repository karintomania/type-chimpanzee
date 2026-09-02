const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "type-chimpanzee",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "run exe");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test
    const exe_test = b.addTest(.{ .root_module = exe.root_module });

    const run_exe_test = b.addRunArtifact(exe_test);

    const test_step = b.step("test", "run test");
    test_step.dependOn(&run_exe_test.step);

    const word = b.addExecutable(.{
        .name = "word",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/process_file.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(word);

    const word_cmd = b.addRunArtifact(word);
    // run_cmd.step.dependOn(b.getInstallStep());

    const word_step = b.step("word", "process word file");
    word_step.dependOn(&word_cmd.step);
}
