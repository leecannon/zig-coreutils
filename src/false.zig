const std = @import("std");
const Context = @import("Context.zig");
const Subcommand = @import("subcommands.zig").Subcommand;

pub const subcommand = Subcommand{
    .name = "false",
    .usage = "",
    .execute = execute,
};

pub fn execute(context: Context) u8 {
    _ = context.checkForHelpOrVersion(subcommand);

    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
