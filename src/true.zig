const std = @import("std");

pub fn execute() u8 {
    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
