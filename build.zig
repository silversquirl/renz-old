const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const dir = try std.fs.cwd().openDir("example", .{ .iterate = true });
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".zig")) {
            continue;
        }
        const basename = entry.name[0 .. entry.name.len - ".zig".len];

        var example = b.addExecutable(
            b.fmt("example-{s}", .{basename}),
            b.fmt("example/{s}", .{entry.name}),
        );

        example.addPackagePath("renz", "renz.zig");
        example.addPackagePath("zgl", "deps/zgl/zgl.zig");
        example.addPackagePath("zglfw", "deps/zglfw/src/main.zig");

        example.linkLibC();
        example.linkSystemLibrary("epoxy");
        example.linkSystemLibrary("glfw3");

        example.setBuildMode(mode);
        example.setTarget(target);
        example.install();

        const run_cmd = example.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(
            b.fmt("example/{s}", .{basename}),
            b.fmt("Run '{s}' example", .{basename}),
        );
        run_step.dependOn(&run_cmd.step);
    }

    var tests = b.addTest("renz.zig");
    tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}
