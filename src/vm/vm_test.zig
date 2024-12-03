const std = @import("std");
const Node = @import("../parser/node.zig");
const Parser = @import("../parser/parser.zig");
const Emitter = @import("emitter.zig");
const VM = @import("vm.zig");

const Errors = VM.Errors;

fn parseProgram(allocator: std.mem.Allocator, source: []const u8) !Node.Block {
    var parser = Parser.init(allocator);
    return parser.parse(allocator, source) catch |err| {
        parser.errors.dump();
        return err;
    };
}

fn emitBytecode(allocator: std.mem.Allocator, source: []const u8) !Emitter.EmitResult {
    const ast = try parseProgram(allocator, source);
    var emitter = Emitter.init(allocator);

    return emitter.emit(ast);
}

fn getValue(allocator: std.mem.Allocator, source: []const u8) !Emitter.Value {
    const result = try emitBytecode(allocator, source);
    var vm = try VM.init(allocator);

    return try vm.exec(result);
}

test "Literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var val = try getValue(allocator, "1;");
    try std.testing.expectEqual(1, val.number);

    val = try getValue(allocator, "\"hello\";");
    try std.testing.expectEqualStrings("hello", val.string);

    val = try getValue(allocator, "true;");
    try std.testing.expect(val.boolean);

    val = try getValue(allocator, "false;");
    try std.testing.expect(!val.boolean);

    val = try getValue(allocator, "null;");
    try std.testing.expectEqual(void, @TypeOf(val.nullVal));

    val = try getValue(allocator, "undefined;");
    try std.testing.expectEqual(void, @TypeOf(val.undefinedVal));
}

test "Binary expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var val = try getValue(allocator, "1 + 1;");
    try std.testing.expectEqual(2, val.number);

    val = try getValue(allocator, "2 - 1;");
    try std.testing.expectEqual(1, val.number);

    val = try getValue(allocator, "2 * 2;");
    try std.testing.expectEqual(4, val.number);

    val = try getValue(allocator, "2 / 2;");
    try std.testing.expectEqual(1, val.number);

    const err = getValue(allocator, "1 / 0;");
    try std.testing.expectError(Errors.DivisionByZero, err);

    val = try getValue(allocator, "2 + 7 * 2 - 6 / 2;");
    try std.testing.expectEqual(13, val.number);
}
