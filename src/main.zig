const std = @import("std");
const Scanner = @import("scanner/scanner.zig");
const Parser = @import("parser/parser.zig");
const Node = @import("parser/node.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "if while";

    var parser = Parser.init(allocator);
    _ = parser.parse(allocator, source) catch |err| {
        parser.errors.dump();
        return err;
    };
}
