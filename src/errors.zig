const std = @import("std");

messages: std.ArrayList([]const u8),

pub fn init(arenaAllocator: std.mem.Allocator) @This() {
    const errors = @This(){
        .messages = std.ArrayList([]const u8).init(arenaAllocator),
    };

    return errors;
}

pub fn add(self: *@This(), arenaAllocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(arenaAllocator, fmt, args);
    try self.messages.append(message);
}

pub fn dump(self: *@This()) void {
    const displayCount = self.messages.items.len > 1;
    for (self.messages.items, 0..) |msg, i| {
        if (displayCount) {
            std.debug.print("error reason {d}: {s}\n", .{ i + 1, msg });
        } else {
            std.debug.print("error reason: {s}\n", .{msg});
        }
    }
}
