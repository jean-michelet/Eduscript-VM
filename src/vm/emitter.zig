const std = @import("std");
const Node = @import("../parser/node.zig");
const Token = @import("../scanner/token.zig");

const Errors = error{ InvalidOperation, EndOfBytecode };

pub const Code = struct {
    bytecode: std.ArrayList(u8),
    constants: std.ArrayList(Value),
};

pub const op_halt: u8 = 0x00;
pub const op_add: u8 = 0x01;
pub const op_sub: u8 = 0x02;
pub const op_mul: u8 = 0x03;
pub const op_div: u8 = 0x04;
pub const op_const: u8 = 0x05;

pub const Value = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    nullVal: void,
    undefinedVal: void,
};

bytecode: std.ArrayList(u8),
constants: std.ArrayList(Value),
constPtr: u8 = 0,

pub fn init(arenaAllocator: std.mem.Allocator) @This() {
    return @This(){ .bytecode = std.ArrayList(u8).init(arenaAllocator), .constants = std.ArrayList(Value).init(arenaAllocator) };
}

pub fn emit(self: *@This(), program: Node.Block) !Code {
    self.bytecode.clearAndFree();
    self.constants.clearAndFree();

    for (program.stmts.items) |stmt| {
        switch (stmt) {
            .expr => |expr| try self.emitExprBytecode(expr),
            else => {},
        }
    }

    return Code{ .bytecode = self.bytecode, .constants = self.constants };
}

pub fn read(self: *@This()) !u8 {
    if (self.index >= self.bytecode.len) {
        return Errors.EndOfBytecode;
    }
    const value = self.bytecode[self.index];
    self.index += 1;
    return value;
}

fn emitExprBytecode(self: *@This(), expr: Node.Expr) !void {
    switch (expr) {
        .literal => |lit| try self.emitLiteral(lit),
        .binary => |binary| {
            try self.emitExprBytecode(binary.left());
            try self.emitExprBytecode(binary.right());

            try self.emitBinaryOp(binary.op);
        },
        else => {},
    }
}

fn emitBinaryOp(self: *@This(), op: Token.Type) !void {
    const opcode = switch (op) {
        .plus => op_add,
        .minus => op_sub,
        .star => op_mul,
        .slash => op_div,
        else => return Errors.InvalidOperation,
    };
    try self.bytecode.append(opcode);
}

fn emitLiteral(self: *@This(), lit: Node.Literal) !void {
    switch (lit) {
        .number => |num| {
            try self.appendConst(Value{ .number = num });
        },
        .string => |str| {
            try self.appendConst(Value{ .string = str });
        },
        .boolean => |boolVal| {
            try self.appendConst(Value{ .boolean = boolVal });
        },
        .nullVal => try self.appendConst(Value{ .nullVal = {} }),
        .undefinedVal => try self.appendConst(Value{ .undefinedVal = {} }),
    }
}

fn appendConst(self: *@This(), val: Value) !void {
    try self.bytecode.append(op_const);
    var current: u8 = self.constPtr;
    var i: u8 = 0;
    var match = false;
    for (self.constants.items) |constant| {
        if (std.mem.eql(u8, @tagName(constant), @tagName(val))) {
            match = switch (constant) {
                .number => constant.number == val.number,
                .string => std.mem.eql(u8, constant.string, val.string),
                .boolean => constant.boolean == val.boolean,
                .nullVal => true,
                .undefinedVal => true,
            };

            if (match) {
                current = i;
                break;
            }
        }
        i += 1;
    }

    try self.bytecode.append(current);

    if (!match) {
        self.constPtr += 1;
        try self.constants.append(val);
    }
}
