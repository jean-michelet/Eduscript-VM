const std = @import("std");
const Token = @import("../scanner/token.zig");

pub const Stmt = union(enum) {
    expr: Expr,
    empty: Empty,
};

pub const Expr = union(enum) { binary: Binary, literal: Literal, identifier: Identifier };

pub const Binary = struct {
    operands: *[2]Expr,
    operator: Token.Type,

    pub fn init(arenaAllocator: std.mem.Allocator, op: Token.Type, left_: Expr, right_: Expr) !@This() {
        const binary = @This(){
            .operands = try arenaAllocator.create([2]Expr),
            .operator = op,
        };

        binary.operands[0] = left_;
        binary.operands[1] = right_;

        return binary;
    }

    pub fn left(self: *const @This()) Expr {
        return self.operands[0];
    }

    pub fn right(self: *const @This()) Expr {
        return self.operands[1];
    }
};

pub const Identifier = struct {
    name: []const u8,
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
