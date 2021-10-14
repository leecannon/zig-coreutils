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

pub const options_def = struct {
    help: bool = false,
    version: bool = false,

    pub const shorthands = .{
        .h = "help",
    };
};

pub fn execute(context: *Context, options: anytype) subcommands.Error!u8 {
    if (options.options.help) {
        context.out().print(usage, .{context.exe_path}) catch {};
        return error.HelpOrVersion;
    }
    if (options.options.version) {
        context.printVersion(name);
        return error.HelpOrVersion;
    }

    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
