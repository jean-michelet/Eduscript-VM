const std = @import("std");
const Parser = @import("parser.zig");
const Node = @import("node.zig");
const Token = @import("../scanner/token.zig");

fn getNodes(allocator: std.mem.Allocator, source: []const u8) ![]Node.Stmt {
    var parser = Parser.init();
    const program = try parser.parse(allocator, source);

    return program.stmts.items;
}

test "Parse function declaration statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "function foo(a: boolean) { return; } function bar(a: boolean, b: number) { return; }");

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqualStrings(nodes[0].fn_decl.id.name, "foo");

    const blockStmts = nodes[0].fn_decl.body.stmts.items;
    try std.testing.expectEqual(1, blockStmts.len);
    try std.testing.expectEqual(Node.Return{ .expr = null }, blockStmts[0].return_);

    const params = nodes[0].fn_decl.params.items;
    try std.testing.expectEqual(1, params.len);
    try std.testing.expectEqualStrings(params[0].id.name, "a");

    const params2 = nodes[1].fn_decl.params.items;
    try std.testing.expectEqual(2, params2.len);
    try std.testing.expectEqualStrings(params2[0].id.name, "a");
    try std.testing.expectEqualStrings(params2[1].id.name, "b");
}

test "Parse var declaration statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "let a: number = 1;let b: IdentifierType = 1;");

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqualStrings(nodes[0].var_decl.id.name, "a");
    try std.testing.expectEqual(nodes[0].var_decl.init.literal.number, 1);
    try std.testing.expectEqual(nodes[0].var_decl.type_.built_in, .number_type);

    try std.testing.expectEqualStrings(nodes[1].var_decl.type_.id.name, "IdentifierType");
}

test "Parse if statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "if (true) { return; } if (true) return; else return;");

    try std.testing.expectEqual(2, nodes.len);

    const returnStmt = Node.Stmt{ .return_ = Node.Return{ .expr = null } };

    const stmt = nodes[0].if_.consequent().?.block.stmts.items[0];
    try std.testing.expectEqual(stmt, returnStmt);

    try std.testing.expectEqual(nodes[0].if_.alternate(), null);

    try std.testing.expectEqual(nodes[1].if_.alternate(), returnStmt);
}

test "Parse while statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "while (true) break;");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqual(nodes[0].while_.test_, Node.Expr{ .literal = Node.Literal{ .boolean = true } });
    try std.testing.expectEqual(nodes[0].while_.body.*, Node.Stmt{ .break_ = Node.Break{} });
}

test "Parse jump statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "continue;break;return;return 1;");

    try std.testing.expectEqual(4, nodes.len);
    try std.testing.expectEqual(nodes[0], Node.Stmt{ .continue_ = Node.Continue{} });
    try std.testing.expectEqual(nodes[1], Node.Stmt{ .break_ = Node.Break{} });

    try std.testing.expectEqual(nodes[2], Node.Stmt{ .return_ = Node.Return{ .expr = null } });

    const expr = Node.Expr{ .literal = Node.Literal{ .number = 1 } };
    try std.testing.expectEqual(nodes[3], Node.Stmt{ .return_ = Node.Return{ .expr = expr } });
}

test "Parse empty statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, ";");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqual(nodes[0], Node.Stmt{ .empty = Node.Empty{} });
}

test "Parse literal expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "1;\"hi\";true;undefined;null;");

    try std.testing.expectEqual(5, nodes.len);
    try std.testing.expectEqual(nodes[0].expr.literal.number, 1);
    try std.testing.expectEqualStrings(nodes[1].expr.literal.string, "hi");
    try std.testing.expect(nodes[2].expr.literal.boolean);
    try std.testing.expectEqual(nodes[3].expr.literal.undefinedVal, {});
    try std.testing.expectEqual(nodes[4].expr.literal.nullVal, {});
}

test "Parse identifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "letter;");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqualStrings(nodes[0].expr.identifier.name, "letter");
}

test "Parse assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "a = 2;");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqualStrings(nodes[0].expr.assign.id.name, "a");
    try std.testing.expectEqual(nodes[0].expr.assign.right.*, Node.Expr{ .literal = Node.Literal{ .number = 2 } });
    try std.testing.expectEqual(nodes[0].expr.assign.op, .assign);
}

test "Parse simple binary expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try testSimpleBinaryExpr(allocator, "1 + 2;", Token.Type.plus);
    try testSimpleBinaryExpr(allocator, "1 - 2;", Token.Type.minus);
    try testSimpleBinaryExpr(allocator, "1 * 2;", Token.Type.star);
    try testSimpleBinaryExpr(allocator, "1 / 2;", Token.Type.slash);
    try testSimpleBinaryExpr(allocator, "1 == 2;", Token.Type.equal);
    try testSimpleBinaryExpr(allocator, "1 != 2;", Token.Type.not_equal);
}

test "Parse right-nested binary expressions with precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try testRightNestedBinaryExpr(allocator, "1 == 2 + 3;", Token.Type.equal, Token.Type.plus);
    try testRightNestedBinaryExpr(allocator, "1 != 2 - 3;", Token.Type.not_equal, Token.Type.minus);

    try testRightNestedBinaryExpr(allocator, "1 + 2 * 3;", Token.Type.plus, Token.Type.star);
    try testRightNestedBinaryExpr(allocator, "1 - 2 / 3;", Token.Type.minus, Token.Type.slash);

    try testRightNestedBinaryExpr(allocator, "1 * (2 + 3);", Token.Type.star, Token.Type.plus);
    try testRightNestedBinaryExpr(allocator, "1 / (2 - 3);", Token.Type.slash, Token.Type.minus);
}

test "Parse left-nested binary expressions with precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try testLeftNestedBinaryExpr(allocator, "(2 + 3) * 1;", Token.Type.star, Token.Type.plus);
    try testLeftNestedBinaryExpr(allocator, "(2 - 3) / 1;", Token.Type.slash, Token.Type.minus);

    try testLeftNestedBinaryExpr(allocator, "2 * 3 + 1;", Token.Type.plus, Token.Type.star);
    try testLeftNestedBinaryExpr(allocator, "2 / 3 - 1;", Token.Type.minus, Token.Type.slash);

    try testLeftNestedBinaryExpr(allocator, "2 + 3 == 1;", Token.Type.equal, Token.Type.plus);
    try testLeftNestedBinaryExpr(allocator, "2 - 3 != 1;", Token.Type.not_equal, Token.Type.minus);

    // For same precedence, parse to left
    try testLeftNestedBinaryExpr(allocator, "2 + 3 - 1;", Token.Type.minus, Token.Type.plus);
    try testLeftNestedBinaryExpr(allocator, "2 - 3 + 1;", Token.Type.plus, Token.Type.minus);
}

fn testBinaryExpr(binary: Node.Binary, expectedOp: Token.Type, left: f64, right: f64) !void {
    try std.testing.expectEqual(binary.op, expectedOp);
    try std.testing.expectEqual(binary.left().literal.number, left);
    try std.testing.expectEqual(binary.right().literal.number, right);
}

fn testSimpleBinaryExpr(allocator: std.mem.Allocator, source: []const u8, expectedOp: Token.Type) !void {
    const nodes = try getNodes(allocator, source);

    try std.testing.expectEqual(1, nodes.len);

    const binary = nodes[0].expr.binary;
    try testBinaryExpr(binary, expectedOp, 1, 2);
}

fn testRightNestedBinaryExpr(allocator: std.mem.Allocator, source: []const u8, topOp: Token.Type, nestedOp: Token.Type) !void {
    const nodes = try getNodes(allocator, source);

    try std.testing.expectEqual(1, nodes.len);

    const binary = nodes[0].expr.binary;

    // The operator with less precedence
    try std.testing.expectEqual(binary.op, topOp);
    try std.testing.expectEqual(binary.left().literal.number, 1);

    try testBinaryExpr(binary.right().binary, nestedOp, 2, 3);
}

fn testLeftNestedBinaryExpr(allocator: std.mem.Allocator, source: []const u8, topOp: Token.Type, nestedOp: Token.Type) !void {
    const nodes = try getNodes(allocator, source);

    try std.testing.expectEqual(1, nodes.len);

    const binary = nodes[0].expr.binary;

    // The operator with less precedence
    try std.testing.expectEqual(binary.op, topOp);
    try std.testing.expectEqual(binary.right().literal.number, 1);

    try testBinaryExpr(binary.left().binary, nestedOp, 2, 3);
}
