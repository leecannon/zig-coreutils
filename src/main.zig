const std = @import("std");
const Context = @import("Context.zig");
const descriptions = @import("descriptions.zig");

pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var arg_iter = std.process.args();

    const context = Context{
        .allocator = &arena.allocator,
        .arg_iter = &arg_iter,
        .std_err = std.io.getStdErr().writer(),
        .std_in = std.io.getStdIn().writer(),
        .std_out = std.io.getStdOut().writer(),
    };

    const name = context.getNextArg() orelse {
        // no name given?
        // TODO: Handle error, is this even possible?
        return 1;
    };

    if (descriptions.executeSubcommand(context, std.fs.path.basename(name))) |ret_val| {
        return ret_val;
    }

    // TODO: Handle Error
    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
