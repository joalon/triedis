const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const trie_mod = b.createModule(.{
        .root_source_file = b.path("src/trie.zig"),
        .target = target,
        .optimize = optimize,
    });

    const resp_mod = b.createModule(.{
        .root_source_file = b.path("src/resp.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    server_mod.addImport("xev", xev.module("xev"));
    server_mod.addImport("trie", trie_mod);
    server_mod.addImport("resp", resp_mod);

    const exe = b.addExecutable(.{
        .name = "triedis",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("server", server_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const resp_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/resp.zig"),
        .target = target,
        .optimize = optimize,
    });

    const trie_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/trie.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_resp_unit_tests = b.addRunArtifact(resp_unit_tests);
    const run_trie_unit_tests = b.addRunArtifact(trie_unit_tests);
    const run_server_unit_tests = b.addRunArtifact(server_unit_tests);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_resp_unit_tests.step);
    test_step.dependOn(&run_trie_unit_tests.step);
    test_step.dependOn(&run_server_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
