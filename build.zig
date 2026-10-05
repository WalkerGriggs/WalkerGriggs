const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    const exe = b.addExecutable(.{ .name = "ssg", .root_module = mod });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addArgs(b.args orelse &.{ "content", "public" });
    b.step("run", "Build the site from content/ into public/").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/markdown.zig"), .target = mod.resolved_target }) });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
