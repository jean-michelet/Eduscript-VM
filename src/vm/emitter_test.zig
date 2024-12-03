const std = @import("std");
const Node = @import("../parser/node.zig");
const Parser = @import("../parser/parser.zig");
const Emitter = @import("emitter.zig");
const VM = @import("vm.zig");

fn parseProgram(allocator: std.mem.Allocator, source: []const u8) !Node.Block {
    var parser = Parser.init(allocator);
    return parser.parse(allocator, source) catch |err| {
        parser.errors.dump();
        return err;
    };
}

fn emitBytecode(allocator: std.mem.Allocator, source: []const u8) !Emitter.Code {
    const ast = try parseProgram(allocator, source);
    var emitter = Emitter.init(allocator);

    return emitter.emit(ast);
}

test "Emit literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try emitBytecode(allocator, "1;\"hello\";true;null;undefined;");

    const constants = result.constants;
    try std.testing.expectEqual(1, constants.items[0].number);
    try std.testing.expectEqualStrings("hello", constants.items[1].string);
    try std.testing.expect(constants.items[2].boolean);
    try std.testing.expectEqual(void, @TypeOf(constants.items[3].nullVal));
    try std.testing.expectEqual(void, @TypeOf(constants.items[4].undefinedVal));

    const bytecode = result.bytecode;
    try std.testing.expectEqual(Emitter.op_const, bytecode.items[0]);
    try std.testing.expectEqual(0, bytecode.items[1]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[2]);
    try std.testing.expectEqual(1, bytecode.items[3]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[4]);
    try std.testing.expectEqual(2, bytecode.items[5]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[6]);
    try std.testing.expectEqual(3, bytecode.items[7]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[8]);
    try std.testing.expectEqual(4, bytecode.items[9]);
}

test "Emit unique constants stack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try emitBytecode(allocator, "1;1;\"hello\";\"hello\";true;true;null;null;undefined;undefined;");

    const bytecode = result.bytecode;
    // Tests all the doubles have the same index
    try std.testing.expectEqual(bytecode.items[1], bytecode.items[3]);
    try std.testing.expectEqual(bytecode.items[5], bytecode.items[7]);
    try std.testing.expectEqual(bytecode.items[9], bytecode.items[11]);
    try std.testing.expectEqual(bytecode.items[13], bytecode.items[15]);
    try std.testing.expectEqual(bytecode.items[17], bytecode.items[19]);

    const constants = result.constants;
    try std.testing.expectEqual(5, constants.items.len);
}

test "Emit binary expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try emitBytecode(allocator, "1+2;");

    const constants = result.constants;
    try std.testing.expectEqual(1, constants.items[0].number);
    try std.testing.expectEqual(2, constants.items[1].number);

    const bytecode = result.bytecode;
    try std.testing.expectEqual(Emitter.op_const, bytecode.items[0]);
    try std.testing.expectEqual(0, bytecode.items[1]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[2]);
    try std.testing.expectEqual(1, bytecode.items[3]);
}

test "Emit complex binary expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try emitBytecode(allocator, "1+4-2;");

    const constants = result.constants;
    try std.testing.expectEqual(1, constants.items[0].number);
    try std.testing.expectEqual(4, constants.items[1].number);
    try std.testing.expectEqual(2, constants.items[2].number);

    const bytecode = result.bytecode;
    try std.testing.expectEqual(Emitter.op_const, bytecode.items[0]);
    try std.testing.expectEqual(0, bytecode.items[1]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[2]);
    try std.testing.expectEqual(1, bytecode.items[3]);

    try std.testing.expectEqual(Emitter.op_add, bytecode.items[4]);

    try std.testing.expectEqual(Emitter.op_const, bytecode.items[5]);
    try std.testing.expectEqual(2, bytecode.items[6]);

    try std.testing.expectEqual(Emitter.op_sub, bytecode.items[7]);
}
