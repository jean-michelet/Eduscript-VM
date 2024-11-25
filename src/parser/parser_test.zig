const std = @import("std");
const Parser = @import("parser.zig");
const Node = @import("node.zig");
const Token = @import("../scanner/token.zig");
const Checker = @import("../semantics/checker.zig");

fn getNodes(allocator: std.mem.Allocator, source: []const u8) ![]Node.Stmt {
    var parser = Parser.init(allocator);
    const program = parser.parse(allocator, source) catch |err| {
        parser.errors.dump();
        return err;
    };

    return program.stmts.items;
}

test "Handle unexpected tokens errors in 'parsePrimaryExpr'" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator);
    const program = parser.parse(allocator, "1 + ;");

    try std.testing.expectError(Parser.Errors.UnexpectedToken, program);
    try std.testing.expectEqualStrings("Unexpected token 'semicolon'.", parser.errors.messages.pop());
}

test "Handle unexpected tokens errors in 'parseTypeOrNull'" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator);
    const program = parser.parse(allocator, "function foo(a: 1");

    try std.testing.expectError(Parser.Errors.UnexpectedToken, program);
    try std.testing.expectEqualStrings("Unexpected token 'number_literal'.", parser.errors.messages.pop());
}

test "Handle unexpected tokens errors in 'expect'" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init(allocator);
    const program = parser.parse(allocator, "if while");

    try std.testing.expectError(Parser.Errors.UnexpectedToken, program);
    try std.testing.expectEqualStrings("Expected token 'left_parenthesis', given 'while_keyword'.", parser.errors.messages.pop());
}

test "Parse function declaration statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "function foo(a: boolean): void { return; } function bar(a: boolean, b: number): void { return; }");

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqualStrings("foo", nodes[0].fn_decl.id.name);
    try std.testing.expectEqual(Checker.BuiltinType.Void, nodes[0].fn_decl.returnType.built_in);

    const blockStmts = nodes[0].fn_decl.body.stmts.items;
    try std.testing.expectEqual(1, blockStmts.len);
    try std.testing.expectEqual(null, blockStmts[0].return_.expr);

    const params = nodes[0].fn_decl.params.items;
    try std.testing.expectEqual(1, params.len);
    try std.testing.expectEqualStrings("a", params[0].id.name);

    const params2 = nodes[1].fn_decl.params.items;
    try std.testing.expectEqual(2, params2.len);
    try std.testing.expectEqualStrings("a", params2[0].id.name);
    try std.testing.expectEqualStrings("b", params2[1].id.name);
}

test "Parse var declaration statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "let a: number = 1;let b: IdentifierType = 1;");

    try std.testing.expectEqual(2, nodes.len);
    try std.testing.expectEqualStrings("a", nodes[0].var_decl.id.name);
    try std.testing.expectEqual(1, nodes[0].var_decl.init.literal.number);
    try std.testing.expectEqual(Checker.BuiltinType.Number, nodes[0].var_decl.type_.built_in);

    try std.testing.expectEqualStrings("IdentifierType", nodes[1].var_decl.type_.id.name);
}

test "Parse if statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "if (true) { return; } if (true) return; else return;");

    try std.testing.expectEqual(2, nodes.len);

    const stmt = nodes[0].if_.consequent().?.block.stmts.items[0];
    try std.testing.expectEqual(null, stmt.return_.expr);
    try std.testing.expectEqual(null, nodes[0].if_.alternate());

    try std.testing.expectEqual(null, nodes[1].if_.alternate().?.return_.expr);
}

test "Parse while statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "while (true) break;");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expect(nodes[0].while_.test_.literal.boolean);
    try std.testing.expectEqual(Node.Break{}, nodes[0].while_.body.*.break_);
}

test "Parse jump statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "continue;break;return;return 1;");

    try std.testing.expectEqual(4, nodes.len);
    try std.testing.expectEqual(Node.Continue{}, nodes[0].continue_);
    try std.testing.expectEqual(Node.Break{}, nodes[1].break_);
    try std.testing.expectEqual(null, nodes[2].return_.expr);
    try std.testing.expectEqual(1, nodes[3].return_.expr.?.literal.number);
}

test "Parse empty statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, ";");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqual(Node.Empty{}, nodes[0].empty);
}

test "Parse function call expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "foo(1, true,); bar();");

    try std.testing.expectEqual(2, nodes.len);

    const fnCall1 = nodes[0].expr.fn_call;
    try std.testing.expectEqualStrings("foo", fnCall1.callee.name);

    const args1 = fnCall1.args.items;
    try std.testing.expectEqual(2, args1.len);
    try std.testing.expectEqual(1, args1[0].literal.number);
    try std.testing.expect(args1[1].literal.boolean);

    const fnCall2 = nodes[1].expr.fn_call;
    try std.testing.expectEqualStrings("bar", fnCall2.callee.name);

    const args2 = fnCall2.args.items;
    try std.testing.expectEqual(0, args2.len);
}

test "Parse literal expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "1;\"hi\";true;undefined;null;");

    try std.testing.expectEqual(5, nodes.len);
    try std.testing.expectEqual(1, nodes[0].expr.literal.number);
    try std.testing.expectEqualStrings("hi", nodes[1].expr.literal.string);
    try std.testing.expect(nodes[2].expr.literal.boolean);
    try std.testing.expectEqual({}, nodes[3].expr.literal.undefinedVal);
    try std.testing.expectEqual({}, nodes[4].expr.literal.nullVal);
}

test "Parse identifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "letter;");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqualStrings("letter", nodes[0].expr.identifier.name);
}

test "Parse assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nodes = try getNodes(allocator, "a = 2;");

    try std.testing.expectEqual(1, nodes.len);
    try std.testing.expectEqualStrings("a", nodes[0].expr.assign.id.name);
    try std.testing.expectEqual(2, nodes[0].expr.assign.right.*.literal.number);
    try std.testing.expectEqual(.assign, nodes[0].expr.assign.op);
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
    try std.testing.expectEqual(topOp, binary.op);
    try std.testing.expectEqual(1, binary.left().literal.number);

    try testBinaryExpr(binary.right().binary, nestedOp, 2, 3);
}

fn testLeftNestedBinaryExpr(allocator: std.mem.Allocator, source: []const u8, topOp: Token.Type, nestedOp: Token.Type) !void {
    const nodes = try getNodes(allocator, source);

    try std.testing.expectEqual(1, nodes.len);

    const binary = nodes[0].expr.binary;

    // The operator with less precedence
    try std.testing.expectEqual(topOp, binary.op);
    try std.testing.expectEqual(1, binary.right().literal.number);

    try testBinaryExpr(binary.left().binary, nestedOp, 2, 3);
}
