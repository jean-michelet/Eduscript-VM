const std = @import("std");
const ErrorAccumulator = @import("errors.zig");

test "Error accumulator" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var errors = ErrorAccumulator.init(allocator);

    // Add some errors
    try errors.add(allocator, "Error {d}: {s}", .{ 1, "Invalid syntax" });
    try errors.add(allocator, "Unexpected token: {s}", .{";"});

    try std.testing.expectEqualStrings("Unexpected token: ;", errors.messages.pop());
    try std.testing.expectEqualStrings("Error 1: Invalid syntax", errors.messages.pop());
}
