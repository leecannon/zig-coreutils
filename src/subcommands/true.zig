const std = @import("std");
const Context = @import("../Context.zig");
const subcommands = @import("../subcommands.zig");

pub const name = "true";

pub const usage =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\Exit with a status code indicating success.
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
    \\
;

pub fn execute(context: *Context) subcommands.Error!u8 {
    _ = try context.checkForHelpOrVersion(@This());

    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
