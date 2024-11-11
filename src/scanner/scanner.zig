const std = @import("std");

const Tokens = @import("./token.zig");
const Token = Tokens.Token;
const LiteralValue = Tokens.LiteralValue;
const TokenType = Tokens.TokenType;

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
            '.' => try addToken(&tracker, &tokens, TokenType.Dot, ".", null),
            ':' => try addToken(&tracker, &tokens, TokenType.Colon, ":", null),
            ';' => try addToken(&tracker, &tokens, TokenType.SemiColon, ";", null),
            ',' => try addToken(&tracker, &tokens, TokenType.Coma, ",", null),
            '(' => try addToken(&tracker, &tokens, TokenType.LeftParen, "(", null),
            ')' => try addToken(&tracker, &tokens, TokenType.RightParen, ")", null),
            '{' => try addToken(&tracker, &tokens, TokenType.LeftCBrace, "{", null),
            '}' => try addToken(&tracker, &tokens, TokenType.RightCBrace, "}", null),
            '[' => try addToken(&tracker, &tokens, TokenType.LeftBracket, "[", null),
            ']' => try addToken(&tracker, &tokens, TokenType.RightBracket, "]", null),
            '+',
            => try addToken(&tracker, &tokens, TokenType.Additive, "+", null),
            '-',
            => try addToken(&tracker, &tokens, TokenType.Additive, "-", null),
            '*' => try addToken(&tracker, &tokens, TokenType.Multiplicative, "*", null),
            '/' => {
                if (peekNext(&tracker, source) == '/') {
                    tracker.advanceTo(2); // Skip the '//' characters
                    while (peek(&tracker, source) != '\n' and !isEOF(&tracker, source)) {
                        tracker.advance();
                    }

                    tracker.startPos = tracker.pos;
                } else {
                    // Is a diviser operator
                    try addToken(&tracker, &tokens, TokenType.Multiplicative, "/", null);
                }
            },

            '!' => {
                if (peekNext(&tracker, source) == '=') {
                    try addToken(&tracker, &tokens, TokenType.NotEqual, "!=", null);
                } else {
                    try addToken(&tracker, &tokens, TokenType.Not, "!", null);
                }
            },
            '=' => {
                if (peekNext(&tracker, source) == '=') {
                    try addToken(&tracker, &tokens, TokenType.Equal, "==", null);
                } else {
                    try addToken(&tracker, &tokens, TokenType.Assign, "=", null);
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
        .token_type = TokenType.Eof,
        .lexeme = "",
        .literal = null,
        .line = tracker.line,
        .pos = tracker.startPos,
    });

    return tokens;
}

fn addToken(tracker: *Tracker, tokens: *std.ArrayList(Token), token_type: TokenType, lexeme: []const u8, literal: ?LiteralValue) Errors!void {
    try tokens.append(Token{
        .token_type = token_type,
        .lexeme = lexeme,
        .literal = literal,
        .line = tracker.line,
        .pos = tracker.startPos,
    });
    tracker.advance();
}

fn scanNumber(tracker: *Tracker, tokens: *std.ArrayList(Token), source: []const u8) Errors!void {
    const start = tracker.pos;
    while (tracker.pos < source.len and std.ascii.isDigit(source[tracker.pos])) {
        tracker.advance();
    }

    const lexeme = source[start..tracker.pos];
    const number = try std.fmt.parseFloat(f64, lexeme);

    try addToken(tracker, tokens, TokenType.NumberLiteral, lexeme, LiteralValue{ .number = number });
}

fn scanIdentifierOrKeyword(tracker: *Tracker, tokens: *std.ArrayList(Token), source: []const u8) Errors!void {
    const start = tracker.pos;
    while (!isEOF(tracker, source) and (std.ascii.isAlphanumeric(source[tracker.pos]) or source[tracker.pos] == '_')) {
        tracker.advance();
    }

    const lexeme = source[start..tracker.pos];
    var token_type = TokenType.Identifier;

    if (std.mem.eql(u8, lexeme, "let")) {
        token_type = TokenType.Let;
    } else if (std.mem.eql(u8, lexeme, "function")) {
        token_type = TokenType.Function;
    } else if (std.mem.eql(u8, lexeme, "if")) {
        token_type = TokenType.If;
    } else if (std.mem.eql(u8, lexeme, "else")) {
        token_type = TokenType.Else;
    } else if (std.mem.eql(u8, lexeme, "while")) {
        token_type = TokenType.While;
    } else if (std.mem.eql(u8, lexeme, "return")) {
        token_type = TokenType.Return;
    } else if (std.mem.eql(u8, lexeme, "break")) {
        token_type = TokenType.Break;
    } else if (std.mem.eql(u8, lexeme, "continue")) {
        token_type = TokenType.Continue;
    } else if (std.mem.eql(u8, lexeme, "number")) {
        token_type = TokenType.NumberType;
    } else if (std.mem.eql(u8, lexeme, "string")) {
        token_type = TokenType.StringType;
    } else if (std.mem.eql(u8, lexeme, "boolean")) {
        token_type = TokenType.BooleanType;
    } else if (std.mem.eql(u8, lexeme, "void")) {
        token_type = TokenType.VoidType;
    } else if (std.mem.eql(u8, lexeme, "true") or std.mem.eql(u8, lexeme, "false")) {
        token_type = TokenType.BooleanLiteral;
    } else if (std.mem.eql(u8, lexeme, "null")) {
        token_type = TokenType.NullLiteral;
    } else if (std.mem.eql(u8, lexeme, "undefined")) {
        token_type = TokenType.UndefinedLiteral;
    }

    const literal: ?LiteralValue = switch (token_type) {
        .BooleanLiteral => LiteralValue{ .boolean = std.mem.eql(u8, lexeme, "true") },
        .NullLiteral => LiteralValue{ .null = {} },
        .UndefinedLiteral => LiteralValue{ .undefined = {} },
        else => null,
    };

    try addToken(tracker, tokens, token_type, lexeme, literal);
}

fn scanString(tracker: *Tracker, tokens: *std.ArrayList(Token), source: []const u8, allocator: std.mem.Allocator) Errors!void {
    tracker.advance(); // Skip the opening quote
    const start = tracker.pos;

    while (tracker.pos < source.len and source[tracker.pos] != '"') {
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

    try addToken(tracker, tokens, TokenType.StringLiteral, lexeme, LiteralValue{ .string = lexemeCopy });
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
