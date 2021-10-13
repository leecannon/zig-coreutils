const std = @import("std");
const Context = @import("../Context.zig");
const Subcommand = @import("../subcommands.zig").Subcommand;

pub const subcommand = Subcommand{
    .name = "true",
    .usage = 
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\Exit with a status code indicating success.
    \\
    \\     --help     display this help and exit
    \\     --version  output version information and exit
    \\
    ,
    .execute = execute,
};

pub fn execute(context: *Context) Subcommand.Error!u8 {
    _ = try context.checkForHelpOrVersion(subcommand);

    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
