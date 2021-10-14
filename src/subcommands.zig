const std = @import("std");
const Context = @import("Context.zig");

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/false.zig"),
    @import("subcommands/true.zig"),
};

pub fn executeSubcommand(context: *Context, basename: []const u8) !u8 {
    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) return subcommand.execute(context);
    }

    return error.NoSubcommand;
}

pub const Error = error{
    OutOfMemory,
    HelpOrVersion,
};

comptime {
    std.testing.refAllDecls(@This());
}
