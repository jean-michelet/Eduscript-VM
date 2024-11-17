const std = @import("std");
const Token = @import("./token.zig");

pub const Errors = error{ UnexpectedToken, UnterminatedString } || error{ OutOfMemory, InvalidCharacter };

allocator: std.mem.Allocator,
source: []const u8,
tokens: std.ArrayList(Token),
line: usize,
startPos: usize,
pos: usize,

pub fn init(allocator: std.mem.Allocator, source: []const u8) @This() {
    return @This(){
        .allocator = allocator,
        .source = source,
        .tokens = std.ArrayList(Token).init(allocator),
        .line = 1,
        .startPos = 0,
        .pos = 0,
    };
}

pub fn scanTokens(self: *@This()) Errors!std.ArrayList(Token) {
    self.tokens.clearAndFree();

    while (!self.isEOF()) {
        self.startPos = self.pos;
        const c: u8 = self.source[self.pos];

        switch (c) {
            // Handle single-character tokens
            '.' => try self.addNullToken(Token.Type.dot, "."),
            ':' => try self.addNullToken(Token.Type.colon, ":"),
            ';' => try self.addNullToken(Token.Type.semicolon, ";"),
            ',' => try self.addNullToken(Token.Type.comma, ","),
            '(' => try self.addNullToken(Token.Type.left_paren, "("),
            ')' => try self.addNullToken(Token.Type.right_paren, ")"),
            '{' => try self.addNullToken(Token.Type.left_curly_brace, "{"),
            '}' => try self.addNullToken(Token.Type.right_curly_brace, "}"),
            '[' => try self.addNullToken(Token.Type.left_bracket, "["),
            ']' => try self.addNullToken(Token.Type.right_bracket, "]"),
            '+' => try self.addNullToken(Token.Type.plus, "+"),
            '-' => try self.addNullToken(Token.Type.minus, "-"),
            '*' => try self.addNullToken(Token.Type.star, "*"),
            '/' => {
                if (self.peekNext() == '/') {
                    self.advanceTo(2); // Skip the '//' characters
                    while (self.peek() != '\n' and !self.isEOF()) {
                        self.advance();
                    }
                    self.startPos = self.pos;
                } else {
                    try self.addNullToken(Token.Type.slash, "/");
                }
            },

            '!' => {
                if (self.peekNext() == '=') {
                    self.advance();
                    try self.addNullToken(Token.Type.not_equal, "!=");
                } else {
                    return Errors.UnexpectedToken;
                }
            },
            '=' => {
                if (self.peekNext() == '=') {
                    self.advance();
                    try self.addNullToken(Token.Type.equal, "==");
                } else {
                    try self.addNullToken(Token.Type.assign, "=");
                }
            },
            // Handle whitespace and newlines
            ' ' => self.advance(),
            '\t' => self.advanceTo(4),
            '\n' => self.advanceLine(),
            // Handle numbers
            '0'...'9' => try self.scanNumber(),
            // Handle identifiers and keywords
            'a'...'z', 'A'...'Z', '_' => try self.scanIdentifierOrKeyword(),
            // Handle strings
            '"' => try self.scanString(),
            else => return Errors.UnexpectedToken,
        }
    }

    try self.tokens.append(Token{
        .token_type = Token.Type.eof,
        .lexeme = "",
        .literal = null,
        .line = self.line,
        .pos = self.startPos,
    });

    return self.tokens;
}

fn addToken(self: *@This(), token_type: Token.Type, lexeme: []const u8, literal: ?Token.LiteralValue) Errors!void {
    try self.tokens.append(Token{
        .token_type = token_type,
        .lexeme = lexeme,
        .literal = literal,
        .line = self.line,
        .pos = self.startPos,
    });
}

fn addNullToken(self: *@This(), token_type: Token.Type, lexeme: []const u8) Errors!void {
    try self.addToken(token_type, lexeme, null);
    self.advance();
}

fn scanNumber(self: *@This()) Errors!void {
    const start = self.pos;
    while (!self.isEOF() and std.ascii.isDigit(self.source[self.pos])) {
        self.advance();
    }

    const lexeme = self.source[start..self.pos];
    const number = try std.fmt.parseFloat(f64, lexeme);

    try self.addToken(Token.Type.number_literal, lexeme, Token.LiteralValue{ .number = number });
}

fn scanIdentifierOrKeyword(self: *@This()) Errors!void {
    const start = self.pos;
    while (!self.isEOF() and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) {
        self.advance();
    }

    const lexeme = self.source[start..self.pos];
    var token_type = Token.Type.identifier;

    if (std.mem.eql(u8, lexeme, "let")) {
        token_type = Token.Type.let;
    } else if (std.mem.eql(u8, lexeme, "function")) {
        token_type = Token.Type.function;
    } else if (std.mem.eql(u8, lexeme, "if")) {
        token_type = Token.Type.if_;
    } else if (std.mem.eql(u8, lexeme, "else")) {
        token_type = Token.Type.else_;
    } else if (std.mem.eql(u8, lexeme, "while")) {
        token_type = Token.Type.while_;
    } else if (std.mem.eql(u8, lexeme, "return")) {
        token_type = Token.Type.return_;
    } else if (std.mem.eql(u8, lexeme, "break")) {
        token_type = Token.Type.break_;
    } else if (std.mem.eql(u8, lexeme, "continue")) {
        token_type = Token.Type.continue_;
    } else if (std.mem.eql(u8, lexeme, "number")) {
        token_type = Token.Type.number_type;
    } else if (std.mem.eql(u8, lexeme, "string")) {
        token_type = Token.Type.string_type;
    } else if (std.mem.eql(u8, lexeme, "boolean")) {
        token_type = Token.Type.boolean_type;
    } else if (std.mem.eql(u8, lexeme, "void")) {
        token_type = Token.Type.void_type;
    } else if (std.mem.eql(u8, lexeme, "true") or std.mem.eql(u8, lexeme, "false")) {
        token_type = Token.Type.boolean_literal;
    } else if (std.mem.eql(u8, lexeme, "null")) {
        token_type = Token.Type.null_literal;
    } else if (std.mem.eql(u8, lexeme, "undefined")) {
        token_type = Token.Type.undefined_literal;
    }

    const literal: ?Token.LiteralValue = switch (token_type) {
        .boolean_literal => Token.LiteralValue{ .boolean = std.mem.eql(u8, lexeme, "true") },
        .null_literal => Token.LiteralValue{ .nullVal = {} },
        .undefined_literal => Token.LiteralValue{ .undefinedVal = {} },
        else => null,
    };

    try self.addToken(token_type, lexeme, literal);
}

fn scanString(self: *@This()) Errors!void {
    self.advance(); // Skip the opening quote
    const start = self.pos;

    while (!self.isEOF() and self.source[self.pos] != '"') {
        if (self.source[self.pos] == '\n') {
            self.line += 1;
            self.pos = 0;
        } else {
            self.advance();
        }
    }

    if (self.pos >= self.source.len) {
        return Errors.UnterminatedString;
    }

    const lexeme = self.source[start..self.pos];
    const lexemeCopy = try self.allocator.dupe(u8, lexeme);
    self.advance(); // Skip the closing quote

    try self.addToken(Token.Type.string_literal, lexeme, Token.LiteralValue{ .string = lexemeCopy });
}

fn isEOF(self: *@This()) bool {
    return self.pos >= self.source.len;
}

fn peek(self: *@This()) ?u8 {
    if (self.isEOF()) {
        return null;
    }
    return self.source[self.pos];
}

fn peekNext(self: *@This()) ?u8 {
    if (self.pos + 1 >= self.source.len) {
        return null;
    }
    return self.source[self.pos + 1];
}

fn advance(self: *@This()) void {
    self.advanceTo(1);
}

fn advanceTo(self: *@This(), to: usize) void {
    self.pos += to;
}

fn advanceLine(self: *@This()) void {
    self.line += 1;
    self.pos += 1;
}
