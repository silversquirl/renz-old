//! Highly specialized data URI parser

const std = @import("std");

pub fn parse(allocator: *std.mem.Allocator, uri: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, uri, "data:")) {
        return error.MissingProtocol;
    }
    const comma = std.mem.indexOfScalar(u8, uri, ',') orelse {
        return error.MissingComma;
    };

    if (std.mem.lastIndexOfScalar(u8, uri[0..comma], ';')) |semi| {
        if (std.mem.eql(u8, uri[semi + 1 .. comma], "base64")) {
            const dec = &std.base64.standard.Decoder;
            const len = try dec.calcSizeForSlice(uri[comma + 1 ..]);

            const data = try allocator.alloc(u8, len);
            errdefer allocator.free(data);
            try dec.decode(data, uri[comma + 1 ..]);

            return data;
        }
    }

    unreachable; // TODO: parse urlencoded
}
