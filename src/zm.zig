//! Tiny linear algebra library with vectors, matrices and a few projections
//! Based on vgl.h from https://github.com/vktec/vlib

// This is free and unencumbered software released into the public domain.
//
// Anyone is free to copy, modify, publish, use, compile, sell, or
// distribute this software, either in source code form or as a compiled
// binary, for any purpose, commercial or non-commercial, and by any
// means.
//
// In jurisdictions that recognize copyright laws, the author or authors
// of this software dedicate any and all copyright interest in the
// software to the public domain. We make this dedication for the benefit
// of the public at large and to the detriment of our heirs and
// successors. We intend this dedication to be an overt act of
// relinquishment in perpetuity of all present and future rights to this
// software under copyright law.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
// OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//
// For more information, please refer to <http://unlicense.org/>

const std = @import("std");
const Vector = std.meta.Vector;

pub fn vec(comptime n: comptime_int, x: anytype) std.meta.Vector(n, f32) {
    if (comptime std.meta.trait.isNumber(@TypeOf(x))) {
        return @splat(n, @as(f32, x));
    } else {
        const a: [n]f32 = x;
        return a;
    }
}

test "vec(f32)" {
    try std.testing.expectEqual(
        Vector(3, f32){ 1, 1, 1 },
        vec(3, 1),
    );
}

test "vec([3]f32)" {
    try std.testing.expectEqual(
        Vector(3, f32){ 1, 2, 3 },
        vec(3, [3]f32{ 1, 2, 3 }),
    );
}

test "vec(tuple)" {
    try std.testing.expectEqual(
        Vector(3, f32){ 1, 2, 3 },
        vec(3, .{ 1, 2, 3 }),
    );
}

/// Column-major matrix
pub fn Mat(comptime cols_: comptime_int, comptime rows_: comptime_int) type {
    return struct {
        m: Vector(cols * rows, f32),

        pub const cols: Size = cols_;
        pub const rows: Size = rows_;

        const ColIndex = std.math.IntFittingRange(0, cols - 1);
        const RowIndex = std.math.IntFittingRange(0, rows - 1);
        const Size = std.math.IntFittingRange(0, cols_ * rows_);

        const Self = @This();

        pub fn get(self: Self, x: ColIndex, y: RowIndex) f32 {
            return self.m[@as(Size, x) * rows + y];
        }
        pub fn set(self: *Self, x: ColIndex, y: RowIndex, v: f32) void {
            self.m[@as(Size, x) * rows + y] = v;
        }

        pub fn add(a: Self, b: Self) Self {
            return .{ .m = a.m + b.m };
        }
        pub fn sub(a: Self, b: Self) Self {
            return .{ .m = a.m - b.m };
        }

        pub fn mul(a: Self, b: anytype) Mat(@TypeOf(b).cols, rows) {
            if (cols != @TypeOf(b).rows) {
                @compileError(std.fmt.comptimePrint("Expected matrix with {} rows, got {s}.", .{ cols, @typeName(@TypeOf(b)) }));
            }
            const ocols = @TypeOf(b).cols;
            const orows = rows;

            var r: Mat(ocols, orows) = undefined;
            comptime var x = 0;
            inline while (x < ocols) : (x += 1) {
                comptime var y = 0;
                inline while (y < orows) : (y += 1) {
                    r.set(x, y, @reduce(.Add, a.row(y) * b.col(x)));
                }
            }

            return r;
        }

        fn col(self: Self, comptime x: ColIndex) Vector(rows, f32) {
            const mask = comptime blk: {
                var mask: Vector(rows, i32) = undefined;
                var i: Size = 0;
                while (i < rows) : (i += 1) {
                    mask[i] = x * rows + i;
                }
                break :blk mask;
            };
            // Compiler bug means I can't pass Vector(0, f32){} as b
            return @shuffle(f32, self.m, self.m, mask);
        }

        fn row(self: Self, comptime y: RowIndex) Vector(cols, f32) {
            const mask = comptime blk: {
                var mask: Vector(cols, i32) = undefined;
                var i: Size = 0;
                while (i < cols) : (i += 1) {
                    mask[i] = i * rows + y;
                }
                break :blk mask;
            };
            // Compiler bug means I can't pass Vector(0, f32){} as b
            return @shuffle(f32, self.m, self.m, mask);
        }

        pub fn transpose(self: Self) Self {
            const mask = comptime blk: {
                var mask: Vector(rows * cols, i32) = undefined;
                var x = 0;
                while (x < cols) : (x += 1) {
                    var y = 0;
                    while (y < rows) : (y += 1) {
                        // We insert the row-major index at the column-major position, transposing the matrix
                        mask[x * rows + y] = y * cols + x;
                    }
                }
                break :blk mask;
            };
            // Compiler bug means I can't pass Vector(0, f32){} as b
            const res = @shuffle(f32, self.m, self.m, mask);
            return .{ .m = res };
        }

        /// Convert to row-major flat array
        /// To get a column-major flat array, cast the `m` field
        pub fn toArray(m: Self) [cols * rows]f32 {
            return m.transpose().m;
        }

        /// Convert to column-major nested array
        pub fn colMajor(m: Self) [cols][rows]f32 {
            const a: [rows * cols]f32 = m.m;
            return @bitCast([cols][rows]f32, a);
        }

        /// Convert to row-major nested array
        pub fn rowMajor(m: Self) [rows][cols]f32 {
            return m.transpose().colMajor();
        }
    };
}

/// Construct a (column-major) matrix from a row-major array
pub fn mat(comptime rows: comptime_int, comptime cols: comptime_int, m: [cols * rows]f32) Mat(rows, cols) {
    return (Mat(cols, rows){ .m = m }).transpose();
}

test "mat44 + mat44" {
    const a = mat(4, 4, .{
        1, 2, 3, 4,
        2, 3, 4, 5,
        3, 4, 5, 6,
        4, 5, 6, 7,
    });
    const b = mat(4, 4, .{
        2, 3, 4, 5,
        1, 2, 3, 4,
        4, 5, 6, 7,
        3, 4, 5, 6,
    });

    try std.testing.expectEqual(mat(4, 4, .{
        3, 5, 7,  9,
        3, 5, 7,  9,
        7, 9, 11, 13,
        7, 9, 11, 13,
    }), a.add(b));
}

test "mat44 - mat44" {
    const a = mat(4, 4, .{
        1, 2, 3, 4,
        2, 3, 4, 5,
        3, 4, 5, 6,
        4, 5, 6, 7,
    });
    const b = mat(4, 4, .{
        2, 3, 4, 5,
        1, 2, 3, 4,
        4, 5, 6, 7,
        3, 4, 5, 6,
    });

    try std.testing.expectEqual(mat(4, 4, .{
        -1, -1, -1, -1,
        1,  1,  1,  1,
        -1, -1, -1, -1,
        1,  1,  1,  1,
    }), a.sub(b));
}

test "mat22 * mat22" {
    const a = mat(2, 2, .{
        1, 2,
        3, 4,
    });
    const b = mat(2, 2, .{
        5, 6,
        7, 8,
    });

    try std.testing.expectEqual(mat(2, 2, .{
        19, 22,
        43, 50,
    }), a.mul(b));
}

test "mat44 * mat44" {
    const a = mat(4, 4, .{
        1, 2, 3, 4,
        2, 3, 4, 5,
        3, 4, 5, 6,
        4, 5, 6, 7,
    });
    const b = mat(4, 4, .{
        2, 3, 4, 5,
        1, 2, 3, 4,
        4, 5, 6, 7,
        3, 4, 5, 6,
    });

    try std.testing.expectEqual(mat(4, 4, .{
        28, 38, 48,  58,
        38, 52, 66,  80,
        48, 66, 84,  102,
        58, 80, 102, 124,
    }), a.mul(b));
}

test "transpose mat44" {
    const a = mat(4, 4, .{
        1, 2, 3, 4,
        1, 2, 3, 4,
        1, 2, 3, 4,
        1, 2, 3, 4,
    });

    try std.testing.expectEqual(mat(4, 4, .{
        1, 1, 1, 1,
        2, 2, 2, 2,
        3, 3, 3, 3,
        4, 4, 4, 4,
    }), a.transpose());
}

/// Construct an identity matrix for the given size
pub fn id(comptime n: comptime_int) Mat(n, n) {
    comptime {
        var m = std.mem.zeroes(Mat(n, n));
        var i = 0;
        while (i < n) : (i += 1) {
            m.set(i, i, 1);
        }
        return m;
    }
}

/// Construct a 4x4 matrix from a translation vector
pub fn translate(v: [3]f32) Mat(4, 4) {
    return mat(4, 4, .{
        1, 0, 0, v[0],
        0, 1, 0, v[1],
        0, 0, 1, v[2],
        0, 0, 0, 1,
    });
}

/// Construct a 4x4 matrix from a rotation quaternion
pub fn rotate(q: [4]f32) Mat(4, 4) {
    // Stored as xyzw since that's the order used by GLSL and glTF
    const w = 3;
    const x = 0;
    const y = 1;
    const z = 2;

    return mat(4, 4, .{
        q[w],  q[z],  -q[y], q[x],
        -q[z], q[w],  q[x],  q[y],
        q[y],  -q[x], q[w],  q[z],
        -q[x], -q[y], -q[z], q[w],
    }).mul(mat(4, 4, .{
        q[w],  q[z],  -q[y], -q[x],
        -q[z], q[w],  q[x],  -q[y],
        q[y],  -q[x], q[w],  -q[z],
        q[x],  q[y],  q[z],  q[w],
    }));
}

/// Construct a 4x4 matrix from a  scale vector
pub fn scale(v: [3]f32) Mat(4, 4) {
    return mat(4, 4, .{
        v[0], 0,    0,    0,
        0,    v[1], 0,    0,
        0,    0,    v[2], 0,
        0,    0,    0,    1,
    });
}

test "id4" {
    try std.testing.expectEqual(mat(4, 4, .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }), id(4));
}
