const std = @import("std");
const Scanner = @import("../../src/scanner/scanner.zig");
const Token = @import("../../src/scanner/token.zig");

fn testScanToken(allocator: std.mem.Allocator, source: []const u8, expected_type: Token.Type, expected_lexeme: []const u8) !void {
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
        Token.Type.eof,
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
    try testScanToken(allocator, ".", Token.Type.dot, ".");
    try testScanToken(allocator, ":", Token.Type.colon, ":");
    try testScanToken(allocator, ";", Token.Type.semicolon, ";");
    try testScanToken(allocator, ",", Token.Type.comma, ",");
    try testScanToken(allocator, "(", Token.Type.left_paren, "(");
    try testScanToken(allocator, ")", Token.Type.right_paren, ")");
    try testScanToken(allocator, "{", Token.Type.left_curly_brace, "{");
    try testScanToken(allocator, "}", Token.Type.right_curly_brace, "}");
    try testScanToken(allocator, "[", Token.Type.left_bracket, "[");
    try testScanToken(allocator, "]", Token.Type.right_bracket, "]");
}

test "arithmetic operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "+", Token.Type.additive, "+");
    try testScanToken(allocator, "-", Token.Type.additive, "-");
    try testScanToken(allocator, "*", Token.Type.multiplicative, "*");
    try testScanToken(allocator, "/", Token.Type.multiplicative, "/");
}

test "equality and assignment operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "!", Token.Type.not, "!");
    try testScanToken(allocator, "==", Token.Type.equal, "==");
    try testScanToken(allocator, "!=", Token.Type.not_equal, "!=");
    try testScanToken(allocator, "=", Token.Type.assign, "=");
}

test "keywords and identifiers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(
        allocator,
        "let",
        Token.Type.let,
        "let",
    );
    try testScanToken(allocator, "function", Token.Type.function, "function");
    try testScanToken(allocator, "if", Token.Type.if_, "if");
    try testScanToken(allocator, "else", Token.Type.else_, "else");
    try testScanToken(allocator, "while", Token.Type.while_, "while");
    try testScanToken(allocator, "return", Token.Type.return_, "return");
    try testScanToken(allocator, "break", Token.Type.break_, "break");
    try testScanToken(allocator, "continue", Token.Type.continue_, "continue");
    try testScanToken(allocator, "foo", Token.Type.identifier, "foo");
}

test "type keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "number", Token.Type.number_type, "number");
    try testScanToken(allocator, "string", Token.Type.string_type, "string");
    try testScanToken(allocator, "boolean", Token.Type.boolean_type, "boolean");
    try testScanToken(allocator, "void", Token.Type.void_type, "void");
}

test "literal values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "true", Token.Type.boolean_literal, "true");
    try testScanToken(allocator, "false", Token.Type.boolean_literal, "false");
    try testScanToken(allocator, "null", Token.Type.null_literal, "null");
    try testScanToken(allocator, "undefined", Token.Type.undefined_literal, "undefined");
}

test "identifiers starting with keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testScanToken(allocator, "letVar", Token.Type.identifier, "letVar");
    try testScanToken(allocator, "whileVar", Token.Type.identifier, "whileVar");
}

test "string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try Scanner.scanTokens(allocator, "\"Hello world\"");
    const token = tokens.items[0];

    try std.testing.expectEqual(token.token_type, Token.Type.string_literal);
    try std.testing.expect(std.mem.eql(u8, token.lexeme, "Hello world"));
    try std.testing.expect(std.mem.eql(u8, token.literal.?.string, "Hello world"));
}

test "number literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try Scanner.scanTokens(allocator, "123");
    const token = tokens.items[0];

    try std.testing.expectEqual(token.token_type, Token.Type.number_literal);
    try std.testing.expect(std.mem.eql(u8, token.lexeme, "123"));
    try std.testing.expectEqual(token.literal.?.number, 123);
}

test "boolean literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try Scanner.scanTokens(allocator, "true false");

    try std.testing.expectEqual(tokens.items[0].token_type, Token.Type.boolean_literal);
    try std.testing.expect(std.mem.eql(u8, tokens.items[0].lexeme, "true"));
    try std.testing.expect(tokens.items[0].literal.?.boolean);
}
