const std = @import("std");

pub const Item = enum {
    Loop,
    Function,
};

pub const Stack = struct {
    contexts: std.ArrayList(Item),

    pub fn init(allocator: std.mem.Allocator) Stack {
        return Stack{
            .contexts = std.ArrayList(Item).init(allocator),
        };
    }

    pub fn push(self: *Stack, context: Item) !void {
        try self.contexts.append(context);
    }

    pub fn pop(self: *Stack) void {
        _ = self.contexts.pop();
    }

    pub fn isInContext(self: *Stack, context: Item) bool {
        for (self.contexts.items) |ctx| {
            if (ctx == context) return true;
        }

        return false;
    }
};
