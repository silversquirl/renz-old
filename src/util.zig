const gl = @import("../deps/zgl/zgl.zig");

pub fn loadProgram(comptime name: []const u8) !gl.Program {
    const vert = gl.Shader.create(.vertex);
    vert.source(1, &.{@embedFile("shader/" ++ name ++ ".vert")});
    vert.compile();
    if (vert.get(.compile_status) != 1) {
        return error.ShaderCompileFailed;
    }

    const frag = gl.Shader.create(.fragment);
    frag.source(1, &.{@embedFile("shader/" ++ name ++ ".frag")});
    frag.compile();
    if (frag.get(.compile_status) != 1) {
        return error.ShaderCompileFailed;
    }

    const prog = gl.Program.create();
    prog.attach(vert);
    prog.attach(frag);
    prog.link();
    prog.detach(vert);
    prog.detach(frag);

    if (prog.get(.link_status) != 1) {
        return error.ShaderLinkFailed;
    }

    return prog;
}

pub fn glSizeOf(component_type: gl.Type) usize {
    switch (component_type) {
        .byte => return 1,
        .short => return 2,
        .int => return 4,

        .fixed => return 4,
        .float => return 4,
        .half_float => return 2,
        .double => return 8,

        .unsigned_byte => return 1,
        .unsigned_short => return 2,
        .unsigned_int => return 4,

        .int_2_10_10_10_rev => return 4,
        .unsigned_int_2_10_10_10_rev => return 4,
        .unsigned_int_10_f_11_f_11_f_rev => return 4,
    }
}
