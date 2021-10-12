const std = @import("std");
const Context = @import("Context.zig");
const descriptions = @import("descriptions.zig");

pub const description = descriptions.Description{
    .name = "true",
    .usage = "",
    .execute = execute,
};

pub fn execute(context: Context) u8 {
    _ = context;
    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
