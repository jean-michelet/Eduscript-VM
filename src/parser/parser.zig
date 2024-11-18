const std = @import("std");
const Token = @import("../scanner/token.zig");
const Scanner = @import("../scanner/scanner.zig");
const Node = @import("node.zig");

tokens: []const Token,
current: usize,

pub fn init() @This() {
    return @This(){
        .tokens = &[_]Token{},
        .current = 0,
    };
}

pub fn parse(self: *@This(), arenaAllocator: std.mem.Allocator, source: []const u8) !Node.Program {
    var scannerArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scannerArena.deinit();
    const scannerAllocator = scannerArena.allocator();

    var scanner = Scanner.init(scannerAllocator, source);

    const tokenList = try scanner.scanTokens(scannerAllocator);
    self.tokens = tokenList.items;
    var program = Node.Program{
        .statements = std.ArrayList(Node.Stmt).init(arenaAllocator),
    };

    while (self.current < self.tokens.len and self.peek().token_type != Token.Type.eof) {
        const stmt = try self.parseStatement(arenaAllocator);
        try program.statements.append(stmt);
    }

    return program;
}

fn parseStatement(self: *@This(), arenaAllocator: std.mem.Allocator) !Node.Stmt {
    return try self.parseExprStmt(arenaAllocator);
}

fn parseExprStmt(self: *@This(), arenaAllocator: std.mem.Allocator) !Node.Stmt {
    const expr = try self.parseExpr(arenaAllocator, 0);
    try self.expectAndAvance(Token.Type.semicolon);
    if (expr == null) {
        return Node.Stmt{ .empty = Node.Empty{} };
    }

    return Node.Stmt{ .expr = expr.? };
}

fn parseExpr(self: *@This(), arenaAllocator: std.mem.Allocator, min_precedence: usize) !?Node.Expr {
    var left = try self.parsePrimaryExpr(arenaAllocator);

    // Try to create binary expression node (e.g. 1 + 2, true == false)
    while (self.current < self.tokens.len) {
        var op = self.peek();

        // if precedence == 0, not a binary expression operator
        const precedence = self.getPrecedence(op.token_type);
        if (precedence < min_precedence or precedence == 0) break;

        op = try self.consume(op.token_type);

        const right = try self.parseExpr(arenaAllocator, precedence + 1) orelse unreachable;

        const binary = try Node.Binary.init(arenaAllocator, op.token_type, left.?, right);
        left = Node.Expr{ .binary = binary };
    }

    return left;
}

fn parsePrimaryExpr(self: *@This(), arenaAllocator: std.mem.Allocator) !?Node.Expr {
    if (self.match(Token.Type.number_literal)) {
        // Handle number literal
        const token = try self.consume(Token.Type.number_literal);
        return Node.Expr{
            .literal = Node.Literal{
                .number = token.literal.?.number,
            },
        };
    } else if (self.match(Token.Type.string_literal)) {
        // Handle string literal
        const token = try self.consume(Token.Type.string_literal);

        const value = try arenaAllocator.dupe(u8, token.literal.?.string);
        return Node.Expr{
            .literal = Node.Literal{ .string = value },
        };
    } else if (self.match(Token.Type.boolean_literal)) {
        // Handle boolean literal
        const token = try self.consume(Token.Type.boolean_literal);
        const bool_value = token.literal.?.boolean;
        return Node.Expr{
            .literal = Node.Literal{ .boolean = bool_value },
        };
    } else if (self.match(Token.Type.null_literal)) {
        // Handle null literal
        self.advance();
        return Node.Expr{
            .literal = Node.Literal{ .nullVal = {} },
        };
    } else if (self.match(Token.Type.undefined_literal)) {
        // Handle undefined literal
        self.advance();
        return Node.Expr{
            .literal = Node.Literal{ .undefinedVal = {} },
        };
    }

    return null;
}

fn getPrecedence(_: *@This(), token_type: Token.Type) usize {
    switch (token_type) {
        .equal, .not_equal => return 10,
        .plus, .minus => return 11,
        .star, .slash => return 12,
        else => return 0,
    }
}

fn consume(self: *@This(), token_type: Token.Type) !Token {
    try self.expect(token_type);

    const token = self.tokens[self.current];
    self.advance();
    return token;
}

fn expect(self: *@This(), token_type: Token.Type) !void {
    if (self.peek().token_type != token_type) {
        return error.UnexpectedToken;
    }
}

fn expectAndAvance(self: *@This(), token_type: Token.Type) !void {
    try self.expect(token_type);

    self.advance();
}

fn advance(self: *@This()) void {
    self.current += 1;
}

fn peek(self: *@This()) Token {
    return self.tokens[self.current];
}

fn match(self: *@This(), token_type: Token.Type) bool {
    return self.peek().token_type == token_type;
}
