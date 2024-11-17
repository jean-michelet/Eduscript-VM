const std = @import("std");
const Token = @import("../scanner/token.zig");

pub const Stmt = union(enum) {
    expr: Expr,
    empty: Empty,
};

pub const Expr = union(enum) {
    binary: Binary,
    literal: Literal,
};

pub const Binary = struct {
    left: *Expr,
    operator: Token.Type,
    right: *Expr,
};

pub const Literal = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    nullVal: void,
    undefinedVal: void,
};

pub const Empty = struct {};

pub const Program = struct {
    statements: std.ArrayList(Stmt),
};

pub fn createBinary(allocator: std.mem.Allocator, op: Token.Type, left: Expr, right: Expr) !Binary {
    const binary = Binary{
        .left = try allocator.create(Expr),
        .right = try allocator.create(Expr),
        .operator = op,
    };

    binary.left.* = left;
    binary.right.* = right;

    return binary;
}
