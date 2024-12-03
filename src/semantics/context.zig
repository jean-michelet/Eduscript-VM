const std = @import("std");
const Checker = @import("checker.zig");

pub const Item = union(enum) {
    Loop: void,
    Function: FunctionContext,

    pub const FunctionContext = struct {
        returnType: Checker.Type,
    };
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

    pub fn isInContext(self: *Stack, tag: [:0]const u8) bool {
        for (self.contexts.items) |ctx| {
            if (std.mem.eql(u8, @tagName(ctx), tag)) return true;
        }
        return false;
    }

    pub fn currentFunctionContext(self: *Stack) ?Item.FunctionContext {
        const expectedTag = "Function";
        for (self.contexts.items) |ctx| {
            if (std.mem.eql(u8, @tagName(ctx), expectedTag)) return ctx.Function;
        }

        return null;
    }
};
