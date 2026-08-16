const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zgrayscale",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.use_llvm = true;

    // Link to libspng library:
    exe.root_module.linkSystemLibrary("spng", .{});

    // Link to math library:
    exe.root_module.linkSystemLibrary("m", .{});

    b.installArtifact(exe);
}
