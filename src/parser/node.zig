const std = @import("std");
const Token = @import("../scanner/token.zig");

pub const Block = struct {
    stmts: std.ArrayList(Stmt),
};

pub const Stmt = union(enum) {
    fn_decl: FnDecl,
    var_decl: VarDecl,
    block: Block,
    if_: If,
    while_: While,
    continue_: Continue,
    break_: Break,
    return_: Return,
    empty: Empty,
    expr: Expr,
};

pub const FnDecl = struct {
    id: Identifier,
    params: std.ArrayList(Param),
    body: Block,
};

pub const VarDecl = struct {
    id: Identifier,
    type_: Type,
    init: Expr,
};

pub const If = struct {
    test_: Expr,
    branches: *[2]?Stmt,

    pub fn init(arenaAllocator: std.mem.Allocator, test_: Expr, cons: Stmt, alt: ?Stmt) !@This() {
        const ifStmt = @This(){
            .test_ = test_,
            .branches = try arenaAllocator.create([2]?Stmt),
        };

        ifStmt.branches[0] = cons;
        ifStmt.branches[1] = alt;

        return ifStmt;
    }

    pub fn consequent(self: *const @This()) ?Stmt {
        return self.branches[0];
    }

    pub fn alternate(self: *const @This()) ?Stmt {
        return self.branches[1];
    }
};

pub const While = struct {
    test_: Expr,
    body: *Stmt,

    pub fn init(arenaAllocator: std.mem.Allocator, test_: Expr, body: Stmt) !@This() {
        const whileStmt = @This(){ .test_ = test_, .body = try arenaAllocator.create(Stmt) };

        whileStmt.body.* = body;

        return whileStmt;
    }
};

pub const Break = struct {};

pub const Continue = struct {};

pub const Empty = struct {};

pub const Return = struct { expr: ?Expr };

pub const Expr = union(enum) { binary: Binary, literal: Literal, identifier: Identifier, assign: Assign };

pub const Assign = struct {
    id: Identifier,
    right: *Expr,
    op: Token.Type,

    pub fn init(arenaAllocator: std.mem.Allocator, op: Token.Type, id: Identifier, right: Expr) !@This() {
        const assign = @This(){ .id = id, .right = try arenaAllocator.create(Expr), .op = op };

        assign.right.* = right;

        return assign;
    }
};

pub const Binary = struct {
    operands: *[2]Expr,
    op: Token.Type,

    pub fn init(arenaAllocator: std.mem.Allocator, op: Token.Type, left_: Expr, right_: Expr) !@This() {
        const binary = @This(){
            .operands = try arenaAllocator.create([2]Expr),
            .op = op,
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

pub const Param = struct { id: Identifier, type_: Type };

pub const Type = union(enum) { built_in: Token.Type, id: Identifier };

pub const Literal = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    nullVal: void,
    undefinedVal: void,
};
