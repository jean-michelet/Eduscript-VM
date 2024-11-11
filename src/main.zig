const std = @import("std");
const scanner = @import("./scanner/scanner.zig");
const tokens = @import("./scanner/token.zig");
const TokenType = tokens.TokenType;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "let x = 1;";
    const tokenList = try scanner.scanTokens(allocator, source);

    for (tokenList.items) |token| {
        if (token.token_type == TokenType.Eof) break;

        std.debug.print("Token: \"{s}\" at line {d}, pos {d}\n", .{
            token.lexeme,
            token.line,
            token.pos,
        });
    }
}
