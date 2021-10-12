const std = @import("std");
const Context = @import("Context.zig");
const descriptions = @import("descriptions.zig");

pub const description = descriptions.Description{
    .name = "false",
    .usage = "",
    .execute = execute,
};

pub fn execute(context: Context) u8 {
    _ = context.checkForHelpOrVersion(description);

    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
