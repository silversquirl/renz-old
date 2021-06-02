const std = @import("std");
const gl = @import("../deps/zgl/zgl.zig");

const gltf = @import("gltf.zig");
const util = @import("util.zig");

pub fn Renderer(comptime Context: type, comptime activate: fn (Context) void) type {
    return struct {
        allocator: *std.mem.Allocator,
        context: Context,
        file: gltf.File,

        prog: gl.Program,
        vao: gl.VertexArray,
        buffers: []gl.Buffer,

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator, context: Context, file: gltf.File) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.context = context;
            self.file = file;

            activate(self.context);

            self.prog = try util.loadProgram("opaque");
            errdefer self.prog.delete();

            self.vao = gl.createVertexArray();
            errdefer self.vao.delete();

            if (self.file.scene == null) {
                if (self.file.scenes.len != 1) {
                    return error.NoDefaultScene;
                } else {
                    self.file.scene = &self.file.scenes[0];
                }
            }

            self.buffers = try self.allocator.alloc(gl.Buffer, self.file.buffers.len);
            errdefer self.allocator.free(self.buffers);
            gl.createBuffers(self.buffers);
            errdefer gl.deleteBuffers(self.buffers);
            for (self.file.buffers) |buffer, i| {
                self.buffers[i].storage(u8, buffer.len, buffer.ptr, .{});
            }

            for (self.file.buffer_views) |view, i| {
                if (view.target != .array_buffer) continue;
                self.vao.vertexBuffer(
                    @intCast(u32, i),
                    self.buffers[view.buffer],
                    view.byte_offset,
                    view.byte_stride,
                );
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            gl.deleteBuffers(self.buffers);
            self.allocator.free(self.buffers);

            self.vao.delete();
            self.prog.delete();
            self.file.deinit();
        }

        pub fn draw(self: *Self) void {
            activate(self.context);
            gl.clearColor(0, 0, 0, 0);
            gl.clear(.{ .color = true, .depth = true });

            self.vao.bind();
            defer gl.bindVertexArray(.invalid);
            self.prog.use();
            defer gl.useProgram(.invalid);

            for (self.file.scene.?.nodes) |node| {
                self.drawNode(node.*);
            }
        }

        fn drawNode(self: *Self, node: gltf.Node) void {
            if (node.mesh) |mesh| {
                for (mesh.primitives) |prim| {
                    self.drawPrimitive(prim);
                }
            }

            for (node.children) |child| {
                self.drawNode(child.*);
            }
        }

        fn drawPrimitive(self: *Self, prim: gltf.Mesh.Primitive) void {
            self.bindAttributes(prim.attributes);
            defer self.unbindAttributes(prim.attributes);

            if (prim.indices) |index_accessor| {
                const accessor = self.file.accessors[index_accessor];
                // TODO: don't spam these log messages every frame
                // Maybe also add info on which node or mesh the primitive is attached to
                if (accessor.components != 1) {
                    std.log.warn("Skipping element buffer of non-scalar type", .{});
                    return;
                }
                const elem_type = std.meta.intToEnum(gl.ElementType, @enumToInt(accessor.component_type)) catch {
                    std.log.warn("Skipping element buffer of invalid element type", .{});
                    return;
                };
                const view = self.file.buffer_views[accessor.buffer_view];
                if (view.byte_stride != util.glSizeOf(@intToEnum(gl.Type, @enumToInt(elem_type)))) {
                    std.log.warn("Skipping element buffer of incorrect stride", .{});
                    return;
                }

                gl.bindBuffer(self.buffers[view.buffer], .element_array_buffer);
                gl.drawElements(prim.mode, accessor.count, elem_type, accessor.byte_offset + view.byte_offset);
            } else {
                const count: u32 = inline for (attr_map) |m| {
                    if (@field(prim.attributes, m.name)) |attr| {
                        break self.file.accessors[attr].count;
                    }
                } else {
                    std.log.warn("Skipping primitive with no attributes", .{});
                    return;
                };

                gl.drawArrays(prim.mode, 0, count);
            }
        }

        fn bindAttributes(self: *Self, attrs: gltf.Mesh.Attributes) void {
            inline for (attr_map) |m| {
                if (@field(attrs, m.name)) |attr| {
                    const accessor = self.file.accessors[attr];
                    self.vao.enableVertexAttribute(m.loc);
                    self.vao.attribBinding(m.loc, accessor.buffer_view);
                    self.vao.attribFormat(m.loc, accessor.components, accessor.component_type, accessor.normalized, accessor.byte_offset);
                }
            }
        }
        fn unbindAttributes(self: *Self, attrs: gltf.Mesh.Attributes) void {
            inline for (attr_map) |m| {
                if (@field(attrs, m.name)) |_| {
                    self.vao.disableVertexAttribute(m.loc);
                }
            }
        }

        const attr_map = [_]struct {
            name: []const u8,
            loc: u32,
        }{
            .{ .name = "position", .loc = 0 },
            .{ .name = "normal", .loc = 1 },
        };
    };
}
