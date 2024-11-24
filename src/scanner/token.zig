const std = @import("std");

token_type: Type,
lexeme: []const u8,
literal: ?LiteralValue,
line: usize,
pos: usize,

pub const LiteralValue = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    // `void` represents `null` & `undefined`
    nullVal: void,
    undefinedVal: void,
};

pub const Type = enum {
    // symbols
    dot,
    colon,
    semicolon,
    comma,
    left_paren,
    right_paren,
    left_curly_brace,
    right_curly_brace,
    left_bracket,
    right_bracket,

    // arithmetic operators
    plus,
    minus,
    star,
    slash,

    // equality operators
    equal,
    not_equal,

    // relational operators
    // less_than,
    // greater_than,
    // less_than_or_equal,
    // greater_than_or_equal,

    // logical operators
    // and_,
    // or_,

    // assignment operators
    assign,

    // literals
    number_literal,
    string_literal,
    boolean_literal,
    null_literal,
    undefined_literal,

    // keywords
    let,
    function,
    if_,
    else_,
    while_,
    return_,
    break_,
    continue_,

    // type keywords
    number_type,
    string_type,
    boolean_type,
    void_type,

    // identifier
    identifier,

    // others
    eof,
};

pub fn tokenTypeToString(tokenType: Type) []const u8 {
    return switch (tokenType) {
        .dot => "dot",
        .colon => "colon",
        .semicolon => "semicolon",
        .comma => "comma",
        .left_paren => "left_parenthesis",
        .right_paren => "right_parenthesis",
        .left_curly_brace => "left_curly_brace",
        .right_curly_brace => "right_curly_brace",
        .left_bracket => "left_bracket",
        .right_bracket => "right_bracket",
        .plus => "plus",
        .minus => "minus",
        .star => "star",
        .slash => "slash",
        .equal => "equal",
        .not_equal => "not_equal",
        .assign => "assign",
        .number_literal => "number_literal",
        .string_literal => "string_literal",
        .boolean_literal => "boolean_literal",
        .null_literal => "null_literal",
        .undefined_literal => "undefined_literal",
        .let => "let_keyword",
        .function => "function_keyword",
        .if_ => "if_keyword",
        .else_ => "else_keyword",
        .while_ => "while_keyword",
        .return_ => "return_keyword",
        .break_ => "break_keyword",
        .continue_ => "continue_keyword",
        .number_type => "number_type",
        .string_type => "string_type",
        .boolean_type => "boolean_type",
        .void_type => "void_type",
        .identifier => "identifier",
        .eof => "end_of_file",
    };
}
