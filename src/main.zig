const std = @import("std");
const Scanner = @import("scanner/scanner.zig");
const Parser = @import("parser/parser.zig").Parser;
const Node = @import("parser/node.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "let a = \"hello\";";

    var scanner = Scanner.init(allocator, source);
    const tokenList = try scanner.scanTokens();

    for (tokenList.items) |token| {
        std.debug.print("Token: \"{s}\" at line {d}, pos {d}\n", .{
            token.lexeme,
            token.line,
            token.pos,
        });
    }

    const nodes = try allocator.create([2]f64);
    nodes[0] = 1;
    std.debug.print("array: {d}", .{nodes[0]});
}
