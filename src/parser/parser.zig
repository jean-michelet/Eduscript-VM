const std = @import("std");
const Token = @import("../scanner/token.zig");
const Scanner = @import("../scanner/scanner.zig");
const Node = @import("node.zig");

const Errors = error{} || Scanner.Errors;

tokens: []const Token,
current: usize,

pub fn init() @This() {
    return @This(){
        .tokens = &[_]Token{},
        .current = 0,
    };
}

pub fn parse(self: *@This(), arenaAllocator: std.mem.Allocator, source: []const u8) Errors!Node.Program {
    var scannerArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scannerArena.deinit();
    const scannerAllocator = scannerArena.allocator();

    var scanner = Scanner.init(scannerAllocator, source);

    const tokenList = try scanner.scanTokens(scannerAllocator);
    self.tokens = tokenList.items;
    var program = Node.Program{
        .statements = std.ArrayList(Node.Stmt).init(arenaAllocator),
    };

    while (self.current < self.tokens.len and self.peek().token_type != .eof) {
        const stmt = try self.parseStatement(arenaAllocator);
        try program.statements.append(stmt);
    }

    return program;
}

fn parseStatement(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    return try self.parseExprStmt(arenaAllocator);
}

fn parseExprStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    const expr = try self.parseExpr(arenaAllocator, 0);
    try self.expectAndAvance(.semicolon);
    if (expr == null) {
        return Node.Stmt{ .empty = Node.Empty{} };
    }

    return Node.Stmt{ .expr = expr.? };
}

fn parseExpr(self: *@This(), arenaAllocator: std.mem.Allocator, min_precedence: usize) Errors!?Node.Expr {
    var left = try self.parsePrimaryExpr(arenaAllocator);

    const isAssignment = left != null and switch (left.?) {
        .identifier => self.peek().token_type == .assign,
        else => false,
    };

    if (isAssignment) {
        try self.expectAndAvance(.assign);

        const right = try self.parseExpr(arenaAllocator, 0) orelse unreachable;
        const assign = try Node.Assign.init(arenaAllocator, .assign, left.?.identifier, right);

        return Node.Expr{ .assign = assign };
    }

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

fn parsePrimaryExpr(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!?Node.Expr {
    if (self.match(.identifier)) {
        // Handle identifier expression
        const token = try self.consume(.identifier);
        const name = try arenaAllocator.dupe(u8, token.lexeme);

        return Node.Expr{ .identifier = Node.Identifier{ .name = name } };
    }

    if (self.match(.left_paren)) {
        // Handle parenthesized expression
        try self.expectAndAvance(.left_paren);
        const expr = try self.parseExpr(arenaAllocator, 0) orelse unreachable;
        try self.expectAndAvance(.right_paren);
        return expr;
    }

    if (self.match(.number_literal)) {
        // Handle number literal
        const token = try self.consume(.number_literal);
        return Node.Expr{
            .literal = Node.Literal{
                .number = token.literal.?.number,
            },
        };
    }

    if (self.match(.string_literal)) {
        // Handle string literal
        const token = try self.consume(.string_literal);

        const value = try arenaAllocator.dupe(u8, token.literal.?.string);
        return Node.Expr{
            .literal = Node.Literal{ .string = value },
        };
    }

    if (self.match(.boolean_literal)) {
        // Handle boolean literal
        const token = try self.consume(.boolean_literal);
        const bool_value = token.literal.?.boolean;
        return Node.Expr{
            .literal = Node.Literal{ .boolean = bool_value },
        };
    }

    if (self.match(.null_literal)) {
        // Handle null literal
        self.advance();
        return Node.Expr{
            .literal = Node.Literal{ .nullVal = {} },
        };
    }

    if (self.match(.undefined_literal)) {
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

fn consume(self: *@This(), token_type: Token.Type) Errors!Token {
    try self.expect(token_type);

    const token = self.tokens[self.current];
    self.advance();
    return token;
}

fn expect(self: *@This(), token_type: Token.Type) Errors!void {
    if (self.peek().token_type != token_type) {
        return error.UnexpectedToken;
    }
}

fn expectAndAvance(self: *@This(), token_type: Token.Type) Errors!void {
    try self.expect(token_type);

    self.advance();
}

fn advance(self: *@This()) void {
    self.current += 1;
}

fn peek(self: *@This()) Token {
    return self.peekAt(0);
}

fn peekAt(self: *@This(), at: usize) Token {
    return self.tokens[self.current + at];
}

fn match(self: *@This(), token_type: Token.Type) bool {
    return self.peek().token_type == token_type;
}
