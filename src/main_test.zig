const std = @import("std");

test "main_test" {
    std.debug.print("Running main_test.zig tests\n", .{});
}

test "run scanner tests" {
    _ = @import("errors_test.zig");

    _ = @import("scanner/scanner_test.zig");
    _ = @import("parser/parser_test.zig");
    _ = @import("semantics/checker_test.zig");
    _ = @import("vm/emitter_test.zig");
    _ = @import("vm/vm_test.zig");
}
