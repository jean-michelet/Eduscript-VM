const std = @import("std");
const Token = @import("./token.zig");

pub const Errors = error{ UnexpectedToken, UnterminatedString } || error{ OutOfMemory, InvalidCharacter };

const Tracker = struct {
    line: usize = 1,
    startPos: usize = 0,
    pos: usize = 0,
    fn advance(self: *Tracker) void {
        self.advanceTo(1);
    }

    fn advanceTo(self: *Tracker, to: usize) void {
        self.pos += to;
    }

    fn advanceLine(self: *Tracker) void {
        self.line += 1;
        self.pos += 1;
    }
};

pub fn scanTokens(allocator: std.mem.Allocator, source: []const u8) Errors!std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    var tracker = Tracker{};

    while (!isEOF(&tracker, source)) {
        tracker.startPos = tracker.pos;
        const c: u8 = source[tracker.pos];

        switch (c) {
            // Handle single-character tokens
            '.' => try addNullToken(&tracker, &tokens, Token.Type.dot, "."),
            ':' => try addNullToken(&tracker, &tokens, Token.Type.colon, ":"),
            ';' => try addNullToken(&tracker, &tokens, Token.Type.semicolon, ";"),
            ',' => try addNullToken(&tracker, &tokens, Token.Type.comma, ","),
            '(' => try addNullToken(&tracker, &tokens, Token.Type.left_paren, "("),
            ')' => try addNullToken(&tracker, &tokens, Token.Type.right_paren, ")"),
            '{' => try addNullToken(&tracker, &tokens, Token.Type.left_curly_brace, "{"),
            '}' => try addNullToken(&tracker, &tokens, Token.Type.right_curly_brace, "}"),
            '[' => try addNullToken(&tracker, &tokens, Token.Type.left_bracket, "["),
            ']' => try addNullToken(&tracker, &tokens, Token.Type.right_bracket, "]"),
            '+' => try addNullToken(&tracker, &tokens, Token.Type.plus, "+"),
            '-' => try addNullToken(&tracker, &tokens, Token.Type.minus, "-"),
            '*' => try addNullToken(&tracker, &tokens, Token.Type.star, "*"),
            '/' => {
                if (peekNext(&tracker, source) == '/') {
                    tracker.advanceTo(2); // Skip the '//' characters
                    while (peek(&tracker, source) != '\n' and !isEOF(&tracker, source)) {
                        tracker.advance();
                    }
                    tracker.startPos = tracker.pos;
                } else {
                    try addNullToken(&tracker, &tokens, Token.Type.slash, "/");
                }
            },

            '!' => {
                if (peekNext(&tracker, source) == '=') {
                    tracker.advance();
                    try addNullToken(&tracker, &tokens, Token.Type.not_equal, "!=");
                } else {
                    return Errors.UnexpectedToken;
                }
            },
            '=' => {
                if (peekNext(&tracker, source) == '=') {
                    tracker.advance();
                    try addNullToken(&tracker, &tokens, Token.Type.equal, "==");
                } else {
                    try addNullToken(&tracker, &tokens, Token.Type.assign, "=");
                }
            },
            // Handle whitespace and newlines
            ' ' => tracker.advance(),
            '\t' => tracker.advanceTo(4),
            '\n' => tracker.advanceLine(),
            // Handle numbers
            '0'...'9' => try scanNumber(&tracker, &tokens, source),
            // Handle identifiers and keywords
            'a'...'z', 'A'...'Z', '_' => try scanIdentifierOrKeyword(&tracker, &tokens, source),
            // Handle strings
            '"' => try scanString(&tracker, &tokens, source, allocator),
            else => return Errors.UnexpectedToken,
        }
    }

    try tokens.append(Token{
        .token_type = Token.Type.eof,
        .lexeme = "",
        .literal = null,
        .line = tracker.line,
        .pos = tracker.startPos,
    });

    return tokens;
}

fn addToken(tracker: *Tracker, tokens: *std.ArrayList(Token), token_type: Token.Type, lexeme: []const u8, literal: ?Token.LiteralValue) Errors!void {
    try tokens.append(Token{
        .token_type = token_type,
        .lexeme = lexeme,
        .literal = literal,
        .line = tracker.line,
        .pos = tracker.startPos,
    });
}

fn addNullToken(tracker: *Tracker, tokens: *std.ArrayList(Token), token_type: Token.Type, lexeme: []const u8) Errors!void {
    try addToken(tracker, tokens, token_type, lexeme, null);
    tracker.advance();
}

fn scanNumber(tracker: *Tracker, tokens: *std.ArrayList(Token), source: []const u8) Errors!void {
    const start = tracker.pos;
    while (!isEOF(tracker, source) and std.ascii.isDigit(source[tracker.pos])) {
        tracker.advance();
    }

    const lexeme = source[start..tracker.pos];
    const number = try std.fmt.parseFloat(f64, lexeme);

    try addToken(tracker, tokens, Token.Type.number_literal, lexeme, Token.LiteralValue{ .number = number });
}

fn scanIdentifierOrKeyword(tracker: *Tracker, tokens: *std.ArrayList(Token), source: []const u8) Errors!void {
    const start = tracker.pos;
    while (!isEOF(tracker, source) and (std.ascii.isAlphanumeric(source[tracker.pos]) or source[tracker.pos] == '_')) {
        tracker.advance();
    }

    const lexeme = source[start..tracker.pos];
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

    try addToken(tracker, tokens, token_type, lexeme, literal);
}

fn scanString(tracker: *Tracker, tokens: *std.ArrayList(Token), source: []const u8, allocator: std.mem.Allocator) Errors!void {
    tracker.advance(); // Skip the opening quote
    const start = tracker.pos;

    while (!isEOF(tracker, source) and source[tracker.pos] != '"') {
        if (source[tracker.pos] == '\n') {
            tracker.line += 1;
            tracker.pos = 0;
        } else {
            tracker.advance();
        }
    }

    if (tracker.pos >= source.len) {
        return Errors.UnterminatedString;
    }

    const lexeme = source[start..tracker.pos];
    const lexemeCopy = try allocator.dupe(u8, lexeme);
    tracker.advance(); // Skip the closing quote

    try addToken(tracker, tokens, Token.Type.string_literal, lexeme, Token.LiteralValue{ .string = lexemeCopy });
}

fn isEOF(tracker: *Tracker, source: []const u8) bool {
    return tracker.pos >= source.len;
}

fn peek(tracker: *Tracker, source: []const u8) ?u8 {
    if (isEOF(tracker, source)) {
        return null;
    }
    return source[tracker.pos];
}

fn peekNext(tracker: *Tracker, source: []const u8) ?u8 {
    if (tracker.pos + 1 >= source.len) {
        return null;
    }
    return source[tracker.pos + 1];
}
