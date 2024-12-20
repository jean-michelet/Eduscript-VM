const std = @import("std");
const Token = @import("../scanner/token.zig");
const Scanner = @import("../scanner/scanner.zig");
const Node = @import("node.zig");
const Checker = @import("../semantics/checker.zig");

const ErrorAccumulator = @import("../errors.zig");

pub const Errors = error{} || Scanner.Errors;

errors: ErrorAccumulator,
tokens: []const Token,
current: usize,

pub fn init(arenaAllocator: std.mem.Allocator) @This() {
    return @This(){ .tokens = &[_]Token{}, .current = 0, .errors = ErrorAccumulator.init(arenaAllocator) };
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
    return switch (self.peek().token_type) {
        .function => try self.parseFnDecl(arenaAllocator),
        .let => try self.parseVarDecl(arenaAllocator),
        .left_curly_brace => try self.parseBlockStmt(arenaAllocator),
        .if_ => try self.parseIfStmt(arenaAllocator),
        .while_ => self.parseWhileStmt(arenaAllocator),
        .semicolon => {
            self.advance();
            return Node.Stmt{ .empty = Node.Empty{} };
        },
        .continue_ => {
            self.advance();
            try self.expectAndAvance(arenaAllocator, .semicolon);
            return Node.Stmt{ .continue_ = Node.Continue{} };
        },
        .break_ => {
            self.advance();
            try self.expectAndAvance(arenaAllocator, .semicolon);
            return Node.Stmt{ .break_ = Node.Break{} };
        },
        .return_ => try self.parseReturnStmt(arenaAllocator),
        else => try self.parseExprStmt(arenaAllocator),
    };
}

fn parseFnDecl(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(arenaAllocator, .function);

    const id = try self.parseIdentifier(arenaAllocator);
    try self.expectAndAvance(arenaAllocator, .left_paren);

    var params = std.ArrayList(Node.Param).init(arenaAllocator);
    while (self.current < self.tokens.len and self.peek().token_type != .eof and self.peek().token_type != .right_paren) {
        const paramId = try self.parseIdentifier(arenaAllocator);
        try self.expectAndAvance(arenaAllocator, .colon);
        const type_ = try self.parseType(arenaAllocator);

        const param = Node.Param{ .id = paramId, .type_ = type_ };
        try params.append(param);

        if (self.peek().token_type != .right_paren) {
            try self.expectAndAvance(arenaAllocator, .comma);
        }
    }

    try self.expectAndAvance(arenaAllocator, .right_paren);

    try self.expectAndAvance(arenaAllocator, .colon);

    const returnType = try self.parseType(arenaAllocator);

    return Node.Stmt{ .fn_decl = Node.FnDecl{ .id = id, .params = params, .body = try self.parseBlock(arenaAllocator), .returnType = returnType } };
}

fn parseVarDecl(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(arenaAllocator, .let);

    const id = try self.parseIdentifier(arenaAllocator);
    try self.expectAndAvance(arenaAllocator, .colon);

    const type_ = try self.parseTypeOrNull(arenaAllocator);

    try self.expectAndAvance(arenaAllocator, .assign);

    const expr = try self.parseExpr(arenaAllocator, 0);

    try self.expectAndAvance(arenaAllocator, .semicolon);

    return Node.Stmt{ .var_decl = Node.VarDecl{ .id = id, .type_ = type_.?, .init = expr } };
}

fn parseBlockStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    return Node.Stmt{ .block = try self.parseBlock(arenaAllocator) };
}

fn parseBlock(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Block {
    try self.expectAndAvance(arenaAllocator, .left_curly_brace);

    var block = Node.Block{
        .stmts = std.ArrayList(Node.Stmt).init(arenaAllocator),
    };

    while (self.current < self.tokens.len and self.peek().token_type != .eof and self.peek().token_type != .right_curly_brace) {
        const stmt = try self.parseStmt(arenaAllocator);
        try block.stmts.append(stmt);
    }
    try self.expectAndAvance(arenaAllocator, .right_curly_brace);

    return block;
}

fn parseIfStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(arenaAllocator, .if_);

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
    try self.expectAndAvance(arenaAllocator, .while_);
    const test_ = try self.parseParenthizedExpr(arenaAllocator);
    return Node.Stmt{ .while_ = try Node.While.init(arenaAllocator, test_, try self.parseStmt(arenaAllocator)) };
}

fn parseReturnStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    try self.expectAndAvance(arenaAllocator, .return_);
    var expr: ?Node.Expr = null;
    if (self.peek().token_type != .semicolon) {
        expr = try self.parseExpr(arenaAllocator, 0);
    }

    try self.expectAndAvance(arenaAllocator, .semicolon);

    return Node.Stmt{ .return_ = Node.Return{ .expr = expr } };
}

fn parseExprStmt(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Stmt {
    const expr = try self.parseExpr(arenaAllocator, 0);

    try self.expectAndAvance(arenaAllocator, .semicolon);

    return Node.Stmt{ .expr = expr };
}

fn parseExpr(self: *@This(), arenaAllocator: std.mem.Allocator, min_precedence: usize) Errors!Node.Expr {
    var left = try self.parsePrimaryExpr(arenaAllocator);

    const isAssignment = switch (left) {
        .identifier => self.peek().token_type == .assign,
        else => false,
    };

    if (isAssignment) {
        try self.expectAndAvance(arenaAllocator, .assign);

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

        op = try self.consume(arenaAllocator, op.token_type);

        const right = try self.parseExpr(arenaAllocator, precedence + 1);

        const binary = try Node.Binary.init(arenaAllocator, op.token_type, left, right);
        left = Node.Expr{ .binary = binary };
    }

    return left;
}

fn parsePrimaryExpr(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Expr {
    return switch (self.peek().token_type) {
        .identifier => {
            const id = try self.parseIdentifier(arenaAllocator);
            if (self.peek().token_type == .left_paren) {
                return try self.parseFnCall(arenaAllocator, id);
            }

            return Node.Expr{ .identifier = id };
        },
        .left_paren => {
            return self.parseParenthizedExpr(arenaAllocator);
        },
        .number_literal => {
            const token = try self.consume(arenaAllocator, .number_literal);
            return Node.Expr{
                .literal = Node.Literal{
                    .number = token.literal.?.number,
                },
            };
        },
        .string_literal => {
            const token = try self.consume(arenaAllocator, .string_literal);
            const value = try arenaAllocator.dupe(u8, token.literal.?.string);
            return Node.Expr{
                .literal = Node.Literal{ .string = value },
            };
        },
        .boolean_literal => {
            const token = try self.consume(arenaAllocator, .boolean_literal);
            const bool_value = token.literal.?.boolean;
            return Node.Expr{
                .literal = Node.Literal{ .boolean = bool_value },
            };
        },
        .null_literal => {
            self.advance();
            return Node.Expr{
                .literal = Node.Literal{ .nullVal = {} },
            };
        },
        .undefined_literal => {
            self.advance();
            return Node.Expr{
                .literal = Node.Literal{ .undefinedVal = {} },
            };
        },
        else => {
            try self.errors.add(arenaAllocator, "Unexpected token '{s}'.", .{Token.tokenTypeToString(self.peek().token_type)});
            return Errors.UnexpectedToken;
        },
    };
}

fn parseFnCall(self: *@This(), arenaAllocator: std.mem.Allocator, callee: Node.Identifier) Errors!Node.Expr {
    try self.expectAndAvance(arenaAllocator, .left_paren);

    var args = std.ArrayList(Node.Expr).init(arenaAllocator);
    while (self.current < self.tokens.len and self.peek().token_type != .right_paren) {
        const arg = try self.parseExpr(arenaAllocator, 0);
        try args.append(arg);

        if (self.peek().token_type == .right_paren) {
            break;
        }
        try self.expectAndAvance(arenaAllocator, .comma);
    }

    try self.expectAndAvance(arenaAllocator, .right_paren);

    return Node.Expr{
        .fn_call = Node.FnCall{
            .callee = callee,
            .args = args,
        },
    };
}

fn parseType(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Type {
    return try self.parseTypeOrNull(arenaAllocator) orelse unreachable;
}

fn parseTypeOrNull(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!?Node.Type {
    var type_: ?Node.Type = null;
    switch (self.peek().token_type) {
        .void_type, .number_type, .string_type, .boolean_type, .null_literal, .undefined_literal => {
            type_ = Node.Type{ .built_in = try typeFromToken(self.peek().token_type) };
            self.advance();
        },
        .identifier => {
            type_ = Node.Type{ .id = try self.parseIdentifier(arenaAllocator) };
        },
        else => {
            try self.errors.add(arenaAllocator, "Unexpected token '{s}'.", .{Token.tokenTypeToString(self.peek().token_type)});
            return Errors.UnexpectedToken;
        },
    }

    return type_;
}

fn parseIdentifier(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Identifier {
    // Handle identifier expression
    const token = try self.consume(arenaAllocator, .identifier);
    const name = try arenaAllocator.dupe(u8, token.lexeme);

    return Node.Identifier{ .name = name };
}

fn parseParenthizedExpr(self: *@This(), arenaAllocator: std.mem.Allocator) Errors!Node.Expr {
    try self.expectAndAvance(arenaAllocator, .left_paren);
    const expr = try self.parseExpr(arenaAllocator, 0);
    try self.expectAndAvance(arenaAllocator, .right_paren);
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

fn typeFromToken(token_type: Token.Type) !Checker.BuiltinType {
    return switch (token_type) {
        .void_type => .Void,
        .number_type => .Number,
        .boolean_type => .Boolean,
        .string_type => .String,
        .null_literal => .Null,
        .undefined_literal => .Undefined,
        else => Errors.UnexpectedToken,
    };
}

fn consume(self: *@This(), arenaAllocator: std.mem.Allocator, token_type: Token.Type) Errors!Token {
    try self.expect(arenaAllocator, token_type);

    const token = self.tokens[self.current];
    self.advance();
    return token;
}

fn expect(self: *@This(), arenaAllocator: std.mem.Allocator, token_type: Token.Type) Errors!void {
    if (self.peek().token_type != token_type) {
        try self.errors.add(arenaAllocator, "Expected token '{s}', given '{s}'.", .{ Token.tokenTypeToString(token_type), Token.tokenTypeToString(self.peek().token_type) });
        return Errors.UnexpectedToken;
    }
}

fn expectAndAvance(self: *@This(), arenaAllocator: std.mem.Allocator, token_type: Token.Type) Errors!void {
    try self.expect(arenaAllocator, token_type);

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
