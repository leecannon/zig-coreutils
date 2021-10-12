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

    const basename = blk: {
        const name_or_err = arg_iter.next(&arena.allocator) orelse {
            // no name given?
            // TODO: Handle error, is this even possible?
            return 1;
        };

        const name = name_or_err catch |err| switch (err) {
            error.OutOfMemory => {
                // TODO: Handle error
                return 1;
            },
            error.InvalidCmdLine => {
                // TODO: Handle error
                return 1;
            },
        };

        break :blk std.fs.path.basename(name);
    };

    if (descriptions.executeSubcommand(context, basename)) |ret_val| {
        return ret_val;
    }

    // TODO: Handle Error
    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
