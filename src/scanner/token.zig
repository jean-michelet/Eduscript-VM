const std = @import("std");

pub const Token = struct {
    token_type: TokenType,
    lexeme: []const u8,
    // `null` if there's no literal value, e.g. symbols and keywords
    literal: ?LiteralValue,
    line: usize,
    pos: usize,
};

pub const LiteralValue = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    // `void` represents `null` & `undefined`
    null: void,
    undefined: void,
};

pub const TokenType = enum {
    // symbols
    Dot,
    Colon,
    SemiColon,
    Coma,
    LeftParen,
    RightParen,
    LeftCBrace,
    RightCBrace,
    LeftBracket,
    RightBracket,

    // arithmetic operators
    Additive,
    Multiplicative,

    // equality operators
    Not,
    Equal,
    NotEqual,

    // relational operators

    // logical operators

    // assignment operators
    Assign,

    // literals
    NumberLiteral,
    StringLiteral,
    BooleanLiteral,
    NullLiteral,
    UndefinedLiteral,

    // keywords
    Let,
    Function,
    If,
    Else,
    While,
    Return,
    Break,
    Continue,

    // type keywords
    NumberType,
    StringType,
    BooleanType,
    VoidType,

    // Identifier
    Identifier,

    // Others
    Eof,
};
