const std = @import("std");
const Scanner = @import("../../src/scanner/scanner.zig");
const Tokens = @import("../../src/scanner/token.zig");
const Token = Tokens.Token;
const LiteralValue = Tokens.LiteralValue;
const TokenType = Tokens.TokenType;

fn testScanToken(allocator: std.mem.Allocator, source: []const u8, expected_type: TokenType, expected_lexeme: []const u8) !void {
    var tokens: std.ArrayList(Token) = try Scanner.scanTokens(allocator, source);
    defer tokens.deinit();
    const token: Token = tokens.items[0];

    try std.testing.expectEqual(
        expected_type,
        token.token_type,
    );
    try std.testing.expect(std.mem.eql(u8, expected_lexeme, token.lexeme));
    try std.testing.expectEqual(1, token.line);
    try std.testing.expectEqual(0, token.pos);
}

test "skip comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\ // first comment
        \\ // second comment
        \\ // third comment
    ;
    const tokens = try Scanner.scanTokens(allocator, source);
    const token = tokens.items[0];

    try std.testing.expectEqual(
        TokenType.Eof,
        token.token_type,
    );
    try std.testing.expectEqual(3, token.line);
    try std.testing.expectEqual(token.pos, source.len);
}

test "skip whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "   12";
    const tokens = try Scanner.scanTokens(allocator, source);
    const token = tokens.items[0];

    try std.testing.expectEqual(token.pos, source.len - 2);
}

test "track current line number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "\n\n 12";

    const tokens = try Scanner.scanTokens(allocator, source);
    const token = tokens.items[0];

    try std.testing.expectEqual(token.line, 3);
}

test "error on invalid token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "@";

    try std.testing.expectError(Scanner.Errors.UnexpectedToken, Scanner.scanTokens(allocator, source));
}

test "single-character and symbol tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, ".", TokenType.Dot, ".");
    try testScanToken(allocator, ":", TokenType.Colon, ":");
    try testScanToken(allocator, ";", TokenType.SemiColon, ";");
    try testScanToken(allocator, ",", TokenType.Coma, ",");
    try testScanToken(allocator, "(", TokenType.LeftParen, "(");
    try testScanToken(allocator, ")", TokenType.RightParen, ")");
    try testScanToken(allocator, "{", TokenType.LeftCBrace, "{");
    try testScanToken(allocator, "}", TokenType.RightCBrace, "}");
    try testScanToken(allocator, "[", TokenType.LeftBracket, "[");
    try testScanToken(allocator, "]", TokenType.RightBracket, "]");
}

test "arithmetic operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "+", TokenType.Additive, "+");
    try testScanToken(allocator, "-", TokenType.Additive, "-");
    try testScanToken(allocator, "*", TokenType.Multiplicative, "*");
    try testScanToken(allocator, "/", TokenType.Multiplicative, "/");
}

test "equality and assignment operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "!", TokenType.Not, "!");
    try testScanToken(allocator, "==", TokenType.Equal, "==");
    try testScanToken(allocator, "!=", TokenType.NotEqual, "!=");
    try testScanToken(allocator, "=", TokenType.Assign, "=");
}

test "keywords and identifiers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(
        allocator,
        "let",
        TokenType.Let,
        "let",
    );
    try testScanToken(allocator, "function", TokenType.Function, "function");
    try testScanToken(allocator, "if", TokenType.If, "if");
    try testScanToken(allocator, "else", TokenType.Else, "else");
    try testScanToken(allocator, "while", TokenType.While, "while");
    try testScanToken(allocator, "return", TokenType.Return, "return");
    try testScanToken(allocator, "break", TokenType.Break, "break");
    try testScanToken(allocator, "continue", TokenType.Continue, "continue");
    try testScanToken(allocator, "foo", TokenType.Identifier, "foo");
}

test "type keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "number", TokenType.NumberType, "number");
    try testScanToken(allocator, "string", TokenType.StringType, "string");
    try testScanToken(allocator, "boolean", TokenType.BooleanType, "boolean");
    try testScanToken(allocator, "void", TokenType.VoidType, "void");
}

test "literal values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "true", TokenType.BooleanLiteral, "true");
    try testScanToken(allocator, "false", TokenType.BooleanLiteral, "false");
    try testScanToken(allocator, "null", TokenType.NullLiteral, "null");
    try testScanToken(allocator, "undefined", TokenType.UndefinedLiteral, "undefined");
}

test "identifiers starting with keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "letVar", TokenType.Identifier, "letVar");
    try testScanToken(allocator, "whileVar", TokenType.Identifier, "whileVar");
}

test "string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try Scanner.scanTokens(allocator, "\"Hello world\"");
    const token = tokens.items[0];

    try std.testing.expectEqual(token.token_type, TokenType.StringLiteral);
    try std.testing.expect(std.mem.eql(u8, token.lexeme, "Hello world"));
    try std.testing.expect(std.mem.eql(u8, token.literal.?.string, "Hello world"));
}

test "number literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try Scanner.scanTokens(allocator, "123");
    const token = tokens.items[0];

    try std.testing.expectEqual(token.token_type, TokenType.NumberLiteral);
    try std.testing.expect(std.mem.eql(u8, token.lexeme, "123"));
    try std.testing.expectEqual(token.literal.?.number, 123);
}

test "boolean literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try Scanner.scanTokens(allocator, "true false");

    try std.testing.expectEqual(tokens.items[0].token_type, TokenType.BooleanLiteral);
    try std.testing.expect(std.mem.eql(u8, tokens.items[0].lexeme, "true"));
    try std.testing.expect(tokens.items[0].literal.?.boolean);
}
