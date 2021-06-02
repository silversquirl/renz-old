const std = @import("std");
const gl = @import("zgl");
const glfw = @import("zglfw");
const renz = @import("renz");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.ClientAPI, @enumToInt(glfw.APIAttribute.OpenGLAPI));
    glfw.windowHint(.ContextVersionMajor, 4);
    glfw.windowHint(.ContextVersionMinor, 5);
    glfw.windowHint(.OpenGLProfile, @enumToInt(glfw.GLProfileAttribute.OpenglCoreProfile));

    glfw.windowHint(.OpenGLForwardCompat, 1);
    glfw.windowHint(.OpenGLDebugContext, 1);

    var win = try glfw.createWindow(800, 600, "Hello Triangle!", null, null);
    defer glfw.destroyWindow(win);

    glfw.makeContextCurrent(win);
    gl.debugMessageCallback({}, debugCallback);
    glfw.makeContextCurrent(null);

    _ = glfw.setFramebufferSizeCallback(win, framebufferSizeCallback);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const file = try renz.File.initGltf(allocator, @embedFile("assets/tri.gltf"), null);
    var ren = renz.Renderer(?*glfw.Window, glfw.makeContextCurrent).init(allocator, win, file) catch |err| {
        file.deinit();
        return err;
    };
    defer ren.deinit();

    while (!glfw.windowShouldClose(win)) {
        ren.draw();
        glfw.swapBuffers(win);
        glfw.pollEvents();
    }
}

fn framebufferSizeCallback(win: *glfw.Window, width: c_int, height: c_int) callconv(.C) void {
    glfw.makeContextCurrent(win);
    gl.viewport(0, 0, @intCast(usize, width), @intCast(usize, height));
}

fn debugCallback(source: gl.DebugSource, type_: gl.DebugMessageType, id: usize, severity: gl.DebugSeverity, message: []const u8) void {
    const log = std.log.scoped(.gl);
    const fmt = "[{s}] {s}: {s}";
    const args = .{
        @tagName(source),
        @tagName(type_),
        message,
    };

    switch (severity) {
        .high => log.crit(fmt, args),
        .medium => log.warn(fmt, args),
        .low => log.notice(fmt, args),
        .notification => log.debug(fmt, args),
    }
}
