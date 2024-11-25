const std = @import("std");
const Node = @import("../parser/node.zig");
const Context = @import("context.zig");
const Checker = @import("checker.zig");

pub const SymbolKind = enum { Variable, Function, Type };

pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    valueType: ?Checker.Type,
    declarations: std.ArrayList(Symbol),

    pub fn init(arenaAllocator: std.mem.Allocator, name: []const u8, kind: SymbolKind, valueType: ?Checker.Type) Symbol {
        return Symbol{
            .name = name,
            .kind = kind,
            .valueType = valueType,
            .declarations = std.ArrayList(Symbol).init(arenaAllocator),
        };
    }
};

pub const Scope = struct {
    parent: ?*Scope,
    symbols: std.StringHashMap(Symbol),

    pub fn init(arenaAllocator: std.mem.Allocator, parent: ?*Scope) Scope {
        return Scope{
            .parent = parent,
            .symbols = std.StringHashMap(Symbol).init(arenaAllocator),
        };
    }

    pub fn get(self: *Scope, name: []const u8) !Symbol {
        var currentScope: ?*Scope = self;
        while (currentScope) |s| {
            const symbol = s.symbols.get(name);
            if (symbol != null) return symbol.?;
            currentScope = s.parent;
        }

        return Checker.SemanticError.UndeclaredIdentifier;
    }

    pub fn getValueType(self: *Scope, name: []const u8) !Checker.Type {
        const symbol = try self.get(name);
        if (symbol.valueType == null) {
            return Checker.SemanticError.UndeclaredIdentifierValue;
        }

        return symbol.valueType.?;
    }

    pub fn getTypeAlias(self: *Scope, arenaAllocator: std.mem.Allocator, name: []const u8) !Checker.Type {
        const symbol = try self.get(name);

        for (symbol.declarations.items) |decSymbol| {
            if (decSymbol.kind == SymbolKind.Type) return Checker.Type{ .id = try arenaAllocator.dupe(u8, name) };
        }

        return Checker.SemanticError.UndeclaredIdentifierType;
    }

    pub fn exists(self: *Scope, name: []const u8) bool {
        var doesExist = true;
        _ = self.get(name) catch {
            doesExist = false;
        };

        return doesExist;
    }
};
