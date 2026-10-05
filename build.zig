const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .link_libc = true,
    });
    mod.addCSourceFiles(.{ .root = b.dependency("md4c", .{}).path("src"), .files = &.{ "md4c.c", "md4c-html.c", "entity.c" } });
    const exe = b.addExecutable(.{ .name = "ssg", .root_module = mod });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addArgs(b.args orelse &.{ "content", "public" });
    b.step("run", "Build the site from content/ into public/").dependOn(&run.step);
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);
}
