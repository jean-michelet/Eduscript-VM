const std = @import("std");
const Parser = @import("../parser/parser.zig");
const Node = @import("../parser/node.zig");
const Symbols = @import("symbols.zig");
const Checker = @import("checker.zig");
const Context = @import("context.zig");

const Result = struct { scope: Symbols.Scope, checked: Checker.CheckResult };

fn parseProgram(allocator: std.mem.Allocator, source: []const u8) !Node.Block {
    var parser = Parser.init(allocator);
    return parser.parse(allocator, source) catch |err| {
        parser.errors.dump();
        return err;
    };
}

fn analyzeProgram(allocator: std.mem.Allocator, source: []const u8) !Result {
    const program = try parseProgram(allocator, source);

    var checker = Checker.init(allocator);
    var globalScope = Symbols.Scope.init(allocator, null);
    var stack = Context.Stack.init(allocator);
    const result = try checker.checkBlock(allocator, program, &globalScope, &stack);

    return Result{ .scope = globalScope, .checked = result };
}

test "Check variable declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try analyzeProgram(allocator, "let a: number = 1;");
    try std.testing.expect(result.scope.symbols.get("a") != null);

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

    const result = try analyzeProgram(allocator, "function foo(a: number): void { return; }");
    try std.testing.expect(result.scope.symbols.get("foo") != null);

    _ = try analyzeProgram(allocator, "let a: number = 1; function b(): number { return a; }");

    const returnIfMismatch = analyzeProgram(allocator, "function b(): number { if (true) { return \"hello\"; } return 2; }");
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, returnIfMismatch);

    const returnIfElseIfMismatch = analyzeProgram(allocator, "function b(): number { if (true) { return true; } else { return 1; } }");
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, returnIfElseIfMismatch);

    const returnIfElseElseMismatch = analyzeProgram(allocator, "function b(): number { if (true) { return 1; } else { return true; } }");
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, returnIfElseElseMismatch);

    try std.testing.expectError(Checker.SemanticError.DuplicateDeclaration, analyzeProgram(allocator, "function foo(a: number): void { return; } function foo(): void { return; }"));
    try std.testing.expectError(Checker.SemanticError.DuplicateDeclaration, analyzeProgram(allocator, "function foo(a: number, a: string): void { return; }"));

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "function foo(a: number): void { return 1; }"));
    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "function b(c: number): boolean { return c + false; }"));
}

test "Return control flow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try analyzeProgram(allocator, "function test(): void { return; }");

    try std.testing.expectError(Checker.SemanticError.ReturnOutsideFunction, analyzeProgram(allocator, "return;"));

    const unreachableAfterReturn = "function test(): void { return; ; // unreachable \n }";
    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableAfterReturn));
}

test "Check if stmt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "if(1) { ; }"));

    var result = try analyzeProgram(allocator, "if(true) { ; }");
    try std.testing.expectEqual(Checker.Flow.Reachable, result.checked.flow);

    result = try analyzeProgram(allocator, "if(true) { ; } else { ; }");
    try std.testing.expectEqual(Checker.Flow.Reachable, result.checked.flow);

    const unreachableCode =
        \\ function test(): void { 
        \\  if (true) { return; } else { return; } 
        \\  return; // unreachable 
        \\ }
    ;
    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableCode));

    const reachableBecauseOfIfCode =
        \\ function test(): void { 
        \\  if (true) { } else { return; } 
        \\  return; // reachable 
        \\ }
    ;
    result = try analyzeProgram(allocator, reachableBecauseOfIfCode);
    try std.testing.expectEqual(Checker.Flow.Reachable, result.checked.flow);

    const reachableBecauseOfElseCode =
        \\ function test(): void { 
        \\  if (true) { return; } else { } 
        \\  return; // reachable 
        \\ }
    ;
    result = try analyzeProgram(allocator, reachableBecauseOfElseCode);
    try std.testing.expectEqual(Checker.Flow.Reachable, result.checked.flow);
}

test "Check while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    _ = try analyzeProgram(allocator, "while(true) { break; }");

    try std.testing.expectError(Checker.SemanticError.TypeMismatch, analyzeProgram(allocator, "while(1) { break; }"));

    try std.testing.expectError(Checker.SemanticError.BreakOutsideLoop, analyzeProgram(allocator, "break;"));

    const unreachableAfterBreak = "while(true) { break; ; // unreachable \n }";
    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableAfterBreak));

    const unreachableAfterBreakingIfCode =
        \\ while(true) { 
        \\ if (true) { break; } else { break; } 
        \\ ; // unreachable 
        \\ }
    ;
    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableAfterBreakingIfCode));

    _ = try analyzeProgram(allocator, "while(true) { continue; }");

    try std.testing.expectError(Checker.SemanticError.ContinueOutsideLoop, analyzeProgram(allocator, "continue;"));

    const unreachableAfterContinue = "while(true) { continue; ; // unreachable \n }";
    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableAfterContinue));

    const unreachableAfterContinueIfCode =
        \\ while(true) { 
        \\ if (true) { continue; } else { continue; } 
        \\ ; // unreachable 
        \\ }
    ;
    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableAfterContinueIfCode));

    const unreachableAfterReturnCode =
        \\ function test(): void { 
        \\  while (true) return;
        \\  return; // unreachable 
        \\ }
    ;

    try std.testing.expectError(Checker.SemanticError.Unreachable, analyzeProgram(allocator, unreachableAfterReturnCode));

    const fnInLoop =
        \\  while (true) {
        \\    function test(): void { 
        \\        return;
        \\    }
        \\  }
    ;

    _ = try analyzeProgram(allocator, fnInLoop);
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
