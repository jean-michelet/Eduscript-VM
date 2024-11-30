const std = @import("std");
const Node = @import("../parser/node.zig");
const Token = @import("../scanner/token.zig");
const Context = @import("context.zig");
const Symbols = @import("symbols.zig");

pub const SemanticError = error{
    DuplicateDeclaration,
    ReturnOutsideFunction,
    BreakOutsideLoop,
    ContinueOutsideLoop,
    UndeclaredIdentifier,
    UndeclaredIdentifierType,
    UndeclaredIdentifierValue,
    UndeclaredFunction,
    Unreachable,
    InvalidArity,
    TypeMismatch,
} || error{OutOfMemory};

pub const Type = union(enum) { built_in: BuiltinType, function: FunctionType, id: []const u8 };

pub const BuiltinType = enum {
    Number,
    String,
    Boolean,
    Void,
    Undefined,
    Null,
};

pub const FunctionType = struct { paramTypes: std.ArrayList(Type), returnType: *Type };

pub const Flow = enum {
    Reachable,
    Unreachable,
};

pub const CheckResult = struct {
    type_: Type,
    flow: Flow,
};

contextStack: Context.Stack,

pub fn init(arenaAllocator: std.mem.Allocator) @This() {
    return @This(){ .contextStack = Context.Stack.init(arenaAllocator) };
}

pub fn check(self: *@This(), arenaAllocator: std.mem.Allocator, stmt: Node.Stmt, scope: *Symbols.Scope, contextStack: *Context.Stack) SemanticError!CheckResult {
    return switch (stmt) {
        .fn_decl => |fnDecl| {
            const type_ = try self.checkFnDecl(arenaAllocator, fnDecl, scope, contextStack);
            return CheckResult{ .type_ = type_, .flow = .Reachable };
        },
        .var_decl => |varDecl| {
            const type_ = try self.checkVarDecl(arenaAllocator, varDecl, scope, contextStack);
            return CheckResult{ .type_ = type_, .flow = .Reachable };
        },
        .block => |blockStmt| {
            var blockScope = Symbols.Scope.init(arenaAllocator, scope);
            return try self.checkBlock(arenaAllocator, blockStmt, &blockScope, contextStack);
        },
        .if_ => |ifStmt| {
            const testType = try self.checkExpr(arenaAllocator, ifStmt.test_, scope, contextStack);
            try expectBoolean(testType);

            var cons = CheckResult{ .type_ = Type{ .built_in = BuiltinType.Void }, .flow = .Reachable };
            if (ifStmt.consequent()) |consStmt| {
                cons = try self.check(arenaAllocator, consStmt, scope, contextStack);
            }

            var alt = CheckResult{ .type_ = Type{ .built_in = BuiltinType.Void }, .flow = .Reachable };
            if (ifStmt.alternate()) |altStmt| {
                alt = try self.check(arenaAllocator, altStmt, scope, contextStack);
            }

            return CheckResult{
                .type_ = alt.type_,
                .flow = if (cons.flow == .Reachable or alt.flow == .Reachable) .Reachable else .Unreachable,
            };
        },
        .while_ => |whileStmt| {
            const testType = try self.checkExpr(arenaAllocator, whileStmt.test_, scope, contextStack);
            try expectBoolean(testType);

            try contextStack.push(.Loop);
            const bodyCheck = try self.check(arenaAllocator, whileStmt.body.*, scope, contextStack);
            contextStack.pop();

            return bodyCheck;
        },
        .return_ => |returnStmt| {
            const ctx = contextStack.currentFunctionContext();
            if (ctx == null) {
                return SemanticError.ReturnOutsideFunction;
            }

            const returnType = if (returnStmt.expr != null) try self.checkExpr(arenaAllocator, returnStmt.expr.?, scope, contextStack) else Type{ .built_in = BuiltinType.Void };
            try compareTypes(ctx.?.returnType, returnType);

            return CheckResult{ .type_ = returnType, .flow = .Unreachable };
        },
        .break_ => |_| {
            if (!contextStack.isInContext("Loop")) {
                return SemanticError.BreakOutsideLoop;
            }

            return CheckResult{ .type_ = Type{ .built_in = BuiltinType.Void }, .flow = .Unreachable };
        },
        .continue_ => |_| {
            if (!contextStack.isInContext("Loop")) {
                return SemanticError.ContinueOutsideLoop;
            }

            return CheckResult{ .type_ = Type{ .built_in = BuiltinType.Void }, .flow = .Unreachable };
        },
        .expr => |exprStmt| {
            const type_ = try self.checkExpr(arenaAllocator, exprStmt, scope, contextStack);
            return CheckResult{ .type_ = type_, .flow = .Reachable };
        },
        .empty => CheckResult{ .type_ = Type{ .built_in = BuiltinType.Void }, .flow = .Reachable },
    };
}

pub fn checkBlock(self: *@This(), arenaAllocator: std.mem.Allocator, block: Node.Block, scope: *Symbols.Scope, contextStack: *Context.Stack) SemanticError!CheckResult {
    var lastResult = CheckResult{ .type_ = Type{ .built_in = BuiltinType.Void }, .flow = .Reachable };

    for (block.stmts.items) |stmt| {
        if (lastResult.flow == .Unreachable) {
            return SemanticError.Unreachable;
        }

        lastResult = try self.check(arenaAllocator, stmt, scope, contextStack);
    }

    return lastResult;
}

fn checkFnDecl(self: *@This(), arenaAllocator: std.mem.Allocator, fnDecl: Node.FnDecl, scope: *Symbols.Scope, contextStack: *Context.Stack) SemanticError!Type {
    const name = fnDecl.id.name;
    if (scope.exists(name)) {
        return SemanticError.DuplicateDeclaration;
    }

    var paramTypes = std.ArrayList(Type).init(arenaAllocator);
    for (fnDecl.params.items) |param| {
        try paramTypes.append(try getType(arenaAllocator, param.type_, scope));
    }

    const fnType = Type{ .function = FunctionType{ .paramTypes = paramTypes, .returnType = try arenaAllocator.create(Type) } };
    fnType.function.returnType.* = try getType(arenaAllocator, fnDecl.returnType, scope);

    const symbol = Symbols.Symbol.init(arenaAllocator, name, .Function, fnType);
    try scope.symbols.put(name, symbol);

    var functionScope = Symbols.Scope.init(arenaAllocator, scope);

    const ctx = Context.Item{ .Function = Context.Item.FunctionContext{ .returnType = fnType.function.returnType.* } };
    try contextStack.push(ctx);

    for (fnDecl.params.items) |param| {
        const paramName = param.id.name;
        if (functionScope.exists(paramName)) {
            return SemanticError.DuplicateDeclaration;
        }

        const paramSymbol = Symbols.Symbol.init(arenaAllocator, paramName, .Variable, try getType(arenaAllocator, param.type_, scope));
        try functionScope.symbols.put(paramName, paramSymbol);
    }

    const blockResult = try self.checkBlock(arenaAllocator, fnDecl.body, &functionScope, contextStack);

    try compareTypes(blockResult.type_, fnType.function.returnType.*);

    contextStack.pop();

    return fnType;
}

fn checkVarDecl(self: *@This(), arenaAllocator: std.mem.Allocator, varDecl: Node.VarDecl, scope: *Symbols.Scope, contextStack: *Context.Stack) SemanticError!Type {
    const name = varDecl.id.name;
    if (scope.exists(name)) {
        return SemanticError.DuplicateDeclaration;
    }

    const symbol = Symbols.Symbol.init(arenaAllocator, name, .Variable, try self.checkExpr(arenaAllocator, varDecl.init, scope, contextStack));
    try scope.symbols.put(name, symbol);

    const initType = try self.checkExpr(arenaAllocator, varDecl.init, scope, contextStack);

    try compareTypes(try getType(arenaAllocator, varDecl.type_, scope), initType);

    return initType;
}

fn checkExpr(self: *@This(), arenaAllocator: std.mem.Allocator, expr: Node.Expr, scope: *Symbols.Scope, contextStack: *Context.Stack) !Type {
    return switch (expr) {
        .assign => |assignExpr| {
            const idType = try scope.getValueType(assignExpr.id.name);
            const assignType = try self.checkExpr(arenaAllocator, assignExpr.right.*, scope, contextStack);

            try compareTypes(idType, assignType);

            return assignType;
        },
        .identifier => |idExpr| {
            return try scope.getValueType(idExpr.name);
        },
        .fn_call => |fnCall| {
            const symbol = try scope.get(fnCall.callee.name);
            const paramTypes = symbol.valueType.?.function.paramTypes.items;

            try checkArity(fnCall.args.items.len, paramTypes.len);

            for (fnCall.args.items, 0..) |argExpr, i| {
                const argType = try self.checkExpr(arenaAllocator, argExpr, scope, contextStack);
                const paramType = paramTypes[i];
                try compareTypes(argType, paramType);
            }

            return symbol.valueType.?.function.returnType.*;
        },
        .binary => |binaryExpr| {
            const left = try self.checkExpr(arenaAllocator, binaryExpr.left(), scope, contextStack);
            const right = try self.checkExpr(arenaAllocator, binaryExpr.right(), scope, contextStack);

            try expectNumber(left);
            try expectNumber(right);

            return left;
        },
        .literal => |lit| {
            const type_: BuiltinType = switch (lit) {
                .number => BuiltinType.Number,
                .string => BuiltinType.String,
                .boolean => BuiltinType.Boolean,
                .nullVal => BuiltinType.Null,
                .undefinedVal => BuiltinType.Undefined,
            };

            return Type{ .built_in = type_ };
        },
    };
}

fn expectNumber(current: Type) !void {
    try compareTypes(current, .{ .built_in = BuiltinType.Number });
}

fn expectBoolean(current: Type) !void {
    try compareTypes(current, .{ .built_in = BuiltinType.Boolean });
}

fn compareTypes(left: Type, right: Type) !void {
    switch (left) {
        .built_in => {
            return switch (right) {
                .built_in => {
                    if (left.built_in != right.built_in) {
                        return SemanticError.TypeMismatch;
                    }
                },
                else => SemanticError.TypeMismatch,
            };
        },
        .function => {},
        .id => {
            return switch (right) {
                .id => {
                    if (!std.mem.eql(u8, left.id, right.id)) {
                        return SemanticError.TypeMismatch;
                    }
                },
                else => SemanticError.TypeMismatch,
            };
        },
    }
}

fn getValueType(type_: Node.Type, scope: *Symbols.Scope) !Type {
    return switch (type_) {
        .built_in => Type{ .built_in = type_.built_in },
        .id => try scope.getValueType(type_.id.name),
    };
}

fn getType(arenaAllocator: std.mem.Allocator, type_: Node.Type, scope: *Symbols.Scope) !Type {
    return switch (type_) {
        .built_in => Type{ .built_in = type_.built_in },
        .id => try scope.getTypeAlias(arenaAllocator, type_.id.name),
    };
}

fn isVoid(type_: Type) bool {
    return switch (type_) {
        .built_in => type_.built_in == BuiltinType.Void,
        else => false,
    };
}

fn checkArity(left: usize, right: usize) !void {
    if (left != right) {
        return SemanticError.InvalidArity;
    }
}
