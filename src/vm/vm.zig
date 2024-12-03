const std = @import("std");
const Checker = @import("../semantics/checker.zig");
const Emitter = @import("emitter.zig");

pub const Errors = error{ DivisionByZero, InvalidOperation, UnknownOpcode };

const Value = Emitter.Value;

ip: usize,
sp: usize,
stack: std.ArrayList(Value),
bytecode: std.ArrayList(u8),
constants: std.ArrayList(Value),

pub fn init(arenaAllocator: std.mem.Allocator) !@This() {
    return @This(){
        .ip = 0,
        .sp = 0,
        .stack = std.ArrayList(Value).init(arenaAllocator),
        .bytecode = std.ArrayList(u8).init(arenaAllocator),
        .constants = std.ArrayList(Value).init(arenaAllocator),
    };
}

pub fn exec(self: *@This(), emitResult: Emitter.EmitResult) !Value {
    self.bytecode = emitResult.bytecode;
    self.constants = emitResult.constants;

    while (self.ip < self.bytecode.items.len) {
        const opcode: u8 = self.nextByte();

        switch (opcode) {
            Emitter.op_const => {
                const idx: u8 = self.nextByte();

                const value = self.constants.items[idx];
                try self.stack.append(value);
            },
            Emitter.op_add, Emitter.op_sub, Emitter.op_div, Emitter.op_mul => {
                const op = opcode;

                const right = self.stack.pop();
                const left = self.stack.pop();

                const result: f64 = switch (op) {
                    Emitter.op_add => left.number + right.number,
                    Emitter.op_sub => left.number - right.number,
                    Emitter.op_mul => left.number * right.number,
                    Emitter.op_div => if (right.number == 0) return Errors.DivisionByZero else left.number / right.number,
                    else => return Errors.InvalidOperation,
                };

                try self.stack.append(Value{ .number = result });
            },
            else => return Errors.UnknownOpcode,
        }
    }

    return self.stack.pop();
}

fn nextByte(self: *@This()) u8 {
    const opcode: u8 = self.bytecode.items[self.ip];
    self.ip += 1;
    return opcode;
}
