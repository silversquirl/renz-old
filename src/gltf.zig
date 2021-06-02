const std = @import("std");
const gl = @import("../deps/zgl/zgl.zig");

const datauri = @import("datauri.zig");
const util = @import("util.zig");
const zm = @import("zm.zig");

pub const File = struct {
    arena: std.heap.ArenaAllocator,

    scene: ?*Scene,
    scenes: []Scene,
    nodes: []Node,
    meshes: []Mesh,
    buffers: []Buffer,
    buffer_views: []BufferView,
    accessors: []Accessor,

    // Load a glTF file from the raw JSON data, loading necessary files from workdir
    pub fn initGltf(allocator: *std.mem.Allocator, json: []const u8, workdir: ?std.fs.Dir) !File {
        return File.init(allocator, json, &.{ .dir = workdir });
    }
    fn init(allocator: *std.mem.Allocator, json: []const u8, loader: *DataLoader) !File {
        var tmp_arena = std.heap.ArenaAllocator.init(allocator);
        defer tmp_arena.deinit();
        var tmp = try std.json.parse(FileI, &std.json.TokenStream.init(json), .{
            .allocator = &tmp_arena.allocator,
            .ignore_unknown_fields = true,
        });

        return tmp.convert(std.heap.ArenaAllocator.init(allocator), loader);
    }

    pub fn deinit(self: File) void {
        self.arena.deinit();
    }
};

pub const Scene = struct {
    nodes: []*Node,
};
pub const Node = struct {
    children: []*Node,
    matrix: [4 * 4]f32,
    mesh: ?*Mesh,
};

pub const Mesh = struct {
    primitives: []Primitive,

    pub const Primitive = struct {
        attributes: Attributes,
        indices: ?u32,
        material: ?u32,
        mode: gl.PrimitiveType,
    };
    pub const Attributes = struct {
        position: ?u32,
        normal: ?u32,
    };
};

pub const Buffer = []const u8;
pub const BufferView = struct {
    buffer: usize,
    byte_offset: usize,
    byte_length: usize,
    byte_stride: usize,
    target: gl.BufferTarget,
};
pub const Accessor = struct {
    buffer_view: u32,
    byte_offset: usize,
    components: u5,
    component_type: gl.Type,
    count: u32,
    normalized: bool,
};

// TODO
// pub const Camera = struct {};
// pub const Material = struct {};
// pub const Texture = struct {};
// pub const Image = struct {};
// pub const Sampler = struct {};
// pub const Skin = struct {};
// pub const Animation = struct {};

////// Internal types //////
const DataLoader = struct {
    dir: ?std.fs.Dir = null,
    glb: ?[]const u8 = null,

    /// allocator must be the same one used to allocate glb
    fn load(self: *DataLoader, allocator: *std.mem.Allocator, uri: ?[]const u8) ![]const u8 {
        if (uri) |u| {
            if (std.mem.startsWith(u8, u, "data:")) {
                return datauri.parse(allocator, u);
            } else if (self.dir) |dir| {
                // Open file
                const f = try dir.openFile(u, .{});
                defer f.close();
                return try f.readToEndAlloc(allocator, std.math.maxInt(u64));
            } else {
                return error.WorkDirRequired;
            }
        } else {
            const data = self.glb orelse return error.NoGlbData;
            self.glb = null;
            return data;
        }
    }
};

const FileI = struct {
    scene: ?usize = null,
    scenes: []SceneI = &.{},
    nodes: []NodeI = &.{},
    meshes: []MeshI = &.{},
    buffers: []BufferI = &.{},
    bufferViews: []BufferViewI = &.{},
    accessors: []AccessorI = &.{},

    fn convert(self: FileI, arena: std.heap.ArenaAllocator, loader: *DataLoader) !File {
        var res: File = undefined;
        res.arena = arena;
        const allocator = &res.arena.allocator;

        res.accessors = try allocator.alloc(Accessor, self.accessors.len);
        for (self.accessors) |accessor, i| {
            res.accessors[i] = try accessor.convert(self.bufferViews);
        }

        res.buffer_views = try allocator.alloc(BufferView, self.bufferViews.len);
        for (self.bufferViews) |buffer_view, i| {
            res.buffer_views[i] = try buffer_view.convert();
        }

        res.buffers = try allocator.alloc(Buffer, self.buffers.len);
        for (self.buffers) |buffer, i| {
            res.buffers[i] = try buffer.convert(allocator, loader);
        }

        res.meshes = try allocator.alloc(Mesh, self.meshes.len);
        for (self.meshes) |mesh, i| {
            res.meshes[i] = try mesh.convert(allocator);
        }

        res.nodes = try allocator.alloc(Node, self.nodes.len);
        for (self.nodes) |node, i| {
            res.nodes[i] = try node.convert(allocator, res.nodes, res.meshes);
        }

        res.scenes = try allocator.alloc(Scene, self.scenes.len);
        for (self.scenes) |scene, i| {
            res.scenes[i] = try scene.convert(allocator, res.nodes);
        }

        if (self.scene) |idx| {
            res.scene = &res.scenes[idx];
        }

        return res;
    }
};

const SceneI = struct {
    nodes: []usize = &.{},

    fn convert(self: SceneI, allocator: *std.mem.Allocator, all_nodes: []Node) !Scene {
        const nodes = try allocator.alloc(*Node, self.nodes.len);
        for (self.nodes) |node_idx, i| {
            nodes[i] = &all_nodes[node_idx];
        }
        return Scene{ .nodes = nodes };
    }
};

const NodeI = struct {
    children: []usize = &.{},
    mesh: ?usize,

    matrix: [4 * 4]f32 = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },

    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 },
    scale: [3]f32 = .{ 1, 1, 1 },

    fn convert(self: NodeI, allocator: *std.mem.Allocator, nodes: []Node, meshes: []Mesh) !Node {
        const matrix = zm.translate(self.translation)
            .mul(zm.rotate(self.rotation))
            .mul(zm.scale(self.scale))
            .mul(zm.mat(4, 4, self.matrix))
            .toArray();

        const children = try allocator.alloc(*Node, self.children.len);
        for (self.children) |child_idx, i| {
            children[i] = &nodes[child_idx];
        }

        return Node{
            .children = children,
            .matrix = matrix,
            .mesh = if (self.mesh) |i| &meshes[i] else null,
        };
    }
};

const MeshI = struct {
    primitives: []PrimitiveI,

    fn convert(self: MeshI, allocator: *std.mem.Allocator) !Mesh {
        const primitives = try allocator.alloc(Mesh.Primitive, self.primitives.len);
        errdefer allocator.free(primitives);

        for (self.primitives) |p, i| {
            primitives[i] = .{
                .attributes = .{
                    .position = p.attributes.POSITION,
                    .normal = p.attributes.NORMAL,
                },
                .indices = p.indices,
                .material = p.material,
                .mode = try std.meta.intToEnum(gl.PrimitiveType, p.mode),
            };
        }

        return Mesh{ .primitives = primitives };
    }

    const PrimitiveI = struct {
        attributes: struct {
            POSITION: ?u32,
            NORMAL: ?u32,
        },
        indices: ?u32 = null,
        material: ?u32 = null,
        mode: u32 = 4,
    };
};

const BufferI = struct {
    byteLength: usize,
    uri: ?[]const u8 = null,

    fn convert(self: BufferI, allocator: *std.mem.Allocator, loader: *DataLoader) !Buffer {
        const data = try loader.load(allocator, self.uri);
        if (self.byteLength > data.len) {
            return error.NotEnoughData;
        }
        return data[0..self.byteLength];
    }
};

const BufferViewI = struct {
    buffer: usize,
    byteOffset: usize = 0,
    byteLength: usize,
    byteStride: ?usize = null,
    target: ?u32 = null,

    fn convert(self: BufferViewI) !BufferView {
        return BufferView{
            .buffer = self.buffer,
            .byte_offset = self.byteOffset,
            .byte_length = self.byteLength,
            .byte_stride = self.byteStride orelse 0,
            .target = if (self.target) |t|
                try std.meta.intToEnum(gl.BufferTarget, t)
            else
                .array_buffer,
        };
    }
};

const AccessorI = struct {
    bufferView: u32,
    byteOffset: usize = 0,
    componentType: u32,
    normalized: bool = false,
    count: u32,
    type: []const u8,

    // TODO: sparse accessors

    fn convert(self: AccessorI, viewsi: []BufferViewI) !Accessor {
        const component_type = try std.meta.intToEnum(gl.Type, self.componentType);
        const components = try parseType(self.type);

        if (viewsi[self.bufferView].byteStride == null) {
            viewsi[self.bufferView].byteStride = components * util.glSizeOf(component_type);
        }

        return Accessor{
            .buffer_view = self.bufferView,
            .byte_offset = self.byteOffset,
            .component_type = component_type,
            .components = components,
            .normalized = self.normalized,
            .count = self.count,
        };
    }

    fn parseType(type_name: []const u8) !u5 {
        if (std.mem.eql(u8, type_name, "SCALAR")) {
            return 1;
        } else if (std.mem.eql(u8, type_name, "VEC2")) {
            return 2;
        } else if (std.mem.eql(u8, type_name, "VEC3")) {
            return 3;
        } else if (std.mem.eql(u8, type_name, "VEC4")) {
            return 4;
        } else if (std.mem.eql(u8, type_name, "MAT2")) {
            return 2 * 2;
        } else if (std.mem.eql(u8, type_name, "MAT3")) {
            return 3 * 3;
        } else if (std.mem.eql(u8, type_name, "MAT4")) {
            return 4 * 4;
        } else {
            return error.InvalidType;
        }
    }
};
