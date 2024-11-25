const std = @import("std");
const Node = @import("../parser/node.zig");
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

contextStack: Context.Stack,

pub fn init(arenaAllocator: std.mem.Allocator) @This() {
    return @This(){ .contextStack = Context.Stack.init(arenaAllocator) };
}

pub fn check(self: *@This(), arenaAllocator: std.mem.Allocator, stmt: Node.Stmt, scope: *Symbols.Scope, contextStack: *Context.Stack) SemanticError!Type {
    return switch (stmt) {
        .fn_decl => |fnDecl| {
            return try self.checkFnDecl(arenaAllocator, fnDecl, scope, contextStack);
        },
        .var_decl => |varDecl| {
            return try self.checkVarDecl(arenaAllocator, varDecl, scope, contextStack);
        },
        .block => |blockStmt| {
            var blockScope = Symbols.Scope.init(arenaAllocator, scope);
            return try self.checkBlock(arenaAllocator, blockStmt, &blockScope, contextStack);
        },
        .if_ => |ifStmt| {
            var cons: Type = Type{ .built_in = BuiltinType.Void };
            if (ifStmt.consequent()) |consStmt| {
                cons = try self.check(arenaAllocator, consStmt, scope, contextStack);
            }

            var alt: Type = Type{ .built_in = BuiltinType.Void };
            if (ifStmt.alternate()) |altStmt| {
                alt = try self.check(arenaAllocator, altStmt, scope, contextStack);
            }

            if (alt.built_in != cons.built_in) {
                return SemanticError.TypeMismatch;
            }

            return alt;
        },
        .while_ => |whileStmt| {
            try contextStack.push(.Loop);
            const whileType = try self.check(arenaAllocator, whileStmt.body.*, scope, contextStack);
            contextStack.pop();

            return whileType;
        },
        .return_ => |returnStmt| {
            if (!contextStack.isInContext(.Function)) {
                return SemanticError.ReturnOutsideFunction;
            }

            if (returnStmt.expr == null) {
                return Type{ .built_in = BuiltinType.Void };
            }

            return try self.checkExpr(arenaAllocator, returnStmt.expr.?, scope, contextStack);
        },
        .break_ => |_| {
            if (!contextStack.isInContext(.Loop)) {
                return SemanticError.BreakOutsideLoop;
            }

            return Type{ .built_in = BuiltinType.Void };
        },
        .continue_ => |_| {
            if (!contextStack.isInContext(.Loop)) {
                return SemanticError.ContinueOutsideLoop;
            }

            return Type{ .built_in = BuiltinType.Void };
        },
        .expr => |exprStmt| {
            return try self.checkExpr(arenaAllocator, exprStmt, scope, contextStack);
        },
        .empty => Type{ .built_in = BuiltinType.Void },
    };
}

pub fn checkBlock(self: *@This(), arenaAllocator: std.mem.Allocator, block: Node.Block, scope: *Symbols.Scope, contextStack: *Context.Stack) SemanticError!Type {
    var type_: Type = Type{ .built_in = BuiltinType.Void };
    for (block.stmts.items) |stmt| {
        type_ = try self.check(arenaAllocator, stmt, scope, contextStack);
    }

    return type_;
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
    try contextStack.push(.Function);

    for (fnDecl.params.items) |param| {
        const paramName = param.id.name;
        if (functionScope.exists(paramName)) {
            return SemanticError.DuplicateDeclaration;
        }

        const paramSymbol = Symbols.Symbol.init(arenaAllocator, paramName, .Variable, try getType(arenaAllocator, param.type_, scope));
        try functionScope.symbols.put(paramName, paramSymbol);
    }

    const blockType = try self.checkBlock(arenaAllocator, fnDecl.body, &functionScope, contextStack);

    try compareTypes(blockType, fnType.function.returnType.*);

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

            try compareTypes(left, right);

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
