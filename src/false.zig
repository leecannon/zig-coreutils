const std = @import("std");

pub fn execute() u8 {
    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
