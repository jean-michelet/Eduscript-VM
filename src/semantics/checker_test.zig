const std = @import("std");
const Parser = @import("../parser/parser.zig");
const Node = @import("../parser/node.zig");
const Symbols = @import("symbols.zig");
const Checker = @import("checker.zig");
const Context = @import("context.zig");

fn parseProgram(allocator: std.mem.Allocator, source: []const u8) !Node.Block {
    var parser = Parser.init(allocator);
    return parser.parse(allocator, source) catch |err| {
        parser.errors.dump();
        return err;
    };
}

fn analyzeProgram(allocator: std.mem.Allocator, source: []const u8) !Symbols.Scope {
    const program = try parseProgram(allocator, source);

    var checker = Checker.init(allocator);
    var globalScope = Symbols.Scope.init(allocator, null);
    var stack = Context.Stack.init(allocator);
    _ = try checker.checkBlock(allocator, program, &globalScope, &stack);

    return globalScope;
}

test "Check variable declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scop = try analyzeProgram(allocator, "let a: number = 1;");
    try std.testing.expect(scop.symbols.get("a") != null);

    _ = try analyzeProgram(allocator, "let a: number = 1;let b: number = a;");
    try std.testing.expectError(Checker.SemanticError.UndeclaredIdentifierType, analyzeProgram(allocator, "let a: number = 1;let b: a = a;"));

    try std.testing.expectError(Checker.SemanticError.DuplicateDeclaration, analyzeProgram(allocator, "let a: number = 1; let a: boolean = true;"));
    try std.testing.expectError(Checker.SemanticError.DuplicateDeclaration, analyzeProgram(allocator, "let a: number = 1; function a(): number { return 1; }"));

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "let a: number = true;"));
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "let a: number = 1;let b: boolean = a;"));
}

test "Check function declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scope = try analyzeProgram(allocator, "function foo(a: number): void { return; }");
    try std.testing.expect(scope.symbols.get("foo") != null);

    _ = try analyzeProgram(allocator, "let a: number = 1; function b(): number { return a; }");

    try std.testing.expectError(Checker.SemanticError.DuplicateDeclaration, analyzeProgram(allocator, "function foo(a: number): void { return; } function foo(): void { return; }"));
    try std.testing.expectError(Checker.SemanticError.DuplicateDeclaration, analyzeProgram(allocator, "function foo(a: number, a: string): void { return; }"));

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "function foo(a: number): void { return 1; }"));
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "function b(c: number): boolean { return c + false; }"));
}

test "Check variable assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try analyzeProgram(allocator, "let a: number = 1;");

    try std.testing.expectError(Checker.SemanticError.UndeclaredIdentifier, analyzeProgram(allocator, "a = 2;"));

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "let a: number = 1; a = true;"));
}

test "Check function call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try analyzeProgram(allocator, "function b(c: boolean): boolean { return c + false; } let a: boolean = b(true);");

    try std.testing.expectError(Checker.SemanticError.InvalidArity, analyzeProgram(allocator, "function b(): boolean { return true; } b(1);"));
    try std.testing.expectError(Checker.SemanticError.InvalidArity, analyzeProgram(allocator, "function b(a: number): boolean { return true; } b();"));
    try std.testing.expectError(Checker.SemanticError.InvalidArity, analyzeProgram(allocator, "function b(a: number): boolean { return true; } b(1, 2);"));

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "function b(): boolean { return true; } let a: number = b();"));
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "let a: boolean = true; function b(c: number): boolean { return c + false; } a = b(1);"));
}
