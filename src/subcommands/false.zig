const std = @import("std");
const subcommands = @import("../subcommands.zig");

pub const name = "false";

pub const usage =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\Exit with a status code indicating failure.
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
    \\
;

pub const options_def = struct {
    help: bool = false,
    version: bool = false,

    pub const shorthands = .{
        .h = "help",
    };
};

// context
// .{
//     .allocator
//     .std_err,
//     .std_in,
//     .std_out,
// },

// options
// .{
//     .options,
//     .positionals,
// },

pub fn execute(context: anytype, options: anytype) subcommands.Error!u8 {
    _ = context;
    _ = options;

    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
