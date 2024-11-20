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

pub fn parse(self: *@This(), arenaAllocator: std.mem.Allocator, source: []const u8) Errors!Node.Block {
    var scannerArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scannerArena.deinit();
    const scannerAllocator = scannerArena.allocator();

    var scanner = Scanner.init(scannerAllocator, source);

    const tokenList = try scanner.scanTokens(scannerAllocator);
    self.tokens = tokenList.items;
    var program = Node.Block{
        .stmts = std.ArrayList(Node.Stmt).init(arenaAllocator),
    };

    while (self.current < self.tokens.len and self.peek().token_type != .eof) {
        const stmt = try self.parseStmt(arenaAllocator);
        try program.stmts.append(stmt);
    }

    return program;
}

fn parseStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    if (self.match(.let)) {
        return try self.parseVarDecl(arenaAllocator);
    }

    if (self.match(.left_curly_brace)) {
        return try self.parseBlockStmt(arenaAllocator);
    }

    if (self.match(.if_)) {
        return try self.parseIfStmt(arenaAllocator);
    }

    if (self.match(.while_)) {
        return self.parseWhileStmt(arenaAllocator);
    }

    if (self.match(.semicolon)) {
        self.advance();
        return Node.Stmt{ .empty = Node.Empty{} };
    }

    if (self.match(.continue_)) {
        self.advance();
        try self.expectAndAvance(.semicolon);
        return Node.Stmt{ .continue_ = Node.Continue{} };
    }

    if (self.match(.break_)) {
        self.advance();
        try self.expectAndAvance(.semicolon);
        return Node.Stmt{ .break_ = Node.Break{} };
    }

    if (self.match(.return_)) {
        return try self.parseReturnStmt(arenaAllocator);
    }

    return try self.parseExprStmt(arenaAllocator);
}

fn parseVarDecl(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(.let);

    const id = try self.parseIdentifier(arenaAllocator);
    try self.expectAndAvance(.colon);

    var type_: ?Node.Type = null;
    switch (self.peek().token_type) {
        .void_type, .number_type, .string_type, .boolean_type => {
            type_ = Node.Type{ .built_in = self.peek().token_type };
            self.advance();
        },
        .identifier => {
            type_ = Node.Type{ .id = try self.parseIdentifier(arenaAllocator) };
        },
        else => return Errors.UnexpectedToken,
    }

    try self.expectAndAvance(.assign);

    const expr = try self.parseExpr(arenaAllocator, 0);

    try self.expectAndAvance(.semicolon);

    return Node.Stmt{ .var_decl = Node.VarDecl{ .id = id, .type_ = type_.?, .init = expr } };
}

fn parseBlockStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(.left_curly_brace);

    var blockStmt = Node.Block{
        .stmts = std.ArrayList(Node.Stmt).init(arenaAllocator),
    };

    while (self.current < self.tokens.len and self.peek().token_type != .eof and self.peek().token_type != .right_curly_brace) {
        const stmt = try self.parseStmt(arenaAllocator);
        try blockStmt.stmts.append(stmt);
    }
    try self.expectAndAvance(.right_curly_brace);

    return Node.Stmt{ .block = blockStmt };
}

fn parseIfStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(.if_);

    const test_ = try self.parseParenthizedExpr(arenaAllocator);
    const consequent = try self.parseStmt(arenaAllocator);
    var alternate: ?Node.Stmt = null;

    if (self.peek().token_type == .else_) {
        self.advance();
        alternate = try self.parseStmt(arenaAllocator);
    }

    return Node.Stmt{ .if_ = try Node.If.init(arenaAllocator, test_, consequent, alternate) };
}

fn parseWhileStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(.while_);
    const test_ = try self.parseParenthizedExpr(arenaAllocator);
    return Node.Stmt{ .while_ = try Node.While.init(arenaAllocator, test_, try self.parseStmt(arenaAllocator)) };
}

fn parseReturnStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(.return_);
    var expr: ?Node.Expr = null;
    if (self.peek().token_type != .semicolon) {
        expr = try self.parseExpr(arenaAllocator, 0);
    }

    try self.expectAndAvance(.semicolon);

    return Node.Stmt{ .return_ = Node.Return{ .expr = expr } };
}

fn parseExprStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    const expr = try self.parseExpr(arenaAllocator, 0);

    try self.expectAndAvance(.semicolon);

    return Node.Stmt{ .expr = expr };
}

fn parseExpr(self: *@This(), arenaAllocator: std.mem.Allocator, min_precedence: usize) Errors!Node.Expr {
    var left = try self.parsePrimaryExpr(arenaAllocator);

    const isAssignment = switch (left) {
        .identifier => self.peek().token_type == .assign,
        else => false,
    };

    if (isAssignment) {
        try self.expectAndAvance(.assign);

        const right = try self.parseExpr(arenaAllocator, 0);
        const assign = try Node.Assign.init(arenaAllocator, .assign, left.identifier, right);

        return Node.Expr{ .assign = assign };
    }

    // Try to create binary expression node (e.g. 1 + 2, true == false)
    while (self.current < self.tokens.len) {
        var op = self.peek();

        // if precedence == 0, not a binary expression operator
        const precedence = self.getPrecedence(op.token_type);
        if (precedence < min_precedence or precedence == 0) break;

        op = try self.consume(op.token_type);

        const right = try self.parseExpr(arenaAllocator, precedence + 1);

        const binary = try Node.Binary.init(arenaAllocator, op.token_type, left, right);
        left = Node.Expr{ .binary = binary };
    }

    return left;
}

fn parsePrimaryExpr(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Expr {
    if (self.match(.identifier)) {
        return Node.Expr{ .identifier = try self.parseIdentifier(arenaAllocator) };
    }

    if (self.match(.left_paren)) {
        // Handle parenthesized expression
        return self.parseParenthizedExpr(arenaAllocator);
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

    return Errors.UnexpectedToken;
}

fn parseIdentifier(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Identifier {
    // Handle identifier expression
    const token = try self.consume(.identifier);
    const name = try arenaAllocator.dupe(u8, token.lexeme);

    return Node.Identifier{ .name = name };
}

fn parseParenthizedExpr(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Expr {
    try self.expectAndAvance(.left_paren);
    const expr = try self.parseExpr(arenaAllocator, 0);
    try self.expectAndAvance(.right_paren);
    return expr;
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
    return self.tokens[self.current];
}

fn peekAt(self: *@This(), at: usize) ?Token {
    if (self.current + at >= self.tokens.len) {
        return null;
    }

    return self.tokens[self.current + at];
}

fn match(self: *@This(), token_type: Token.Type) bool {
    return self.peek().token_type == token_type;
}
