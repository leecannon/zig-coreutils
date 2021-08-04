const std = @import("std");

pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var arg_iter = std.process.args();

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

    // Note: This generates better code than ComptimeStringMap as the function call is non-virtual and
    // the functions dont have to all match the same signature exactly
    const len = basename.len;
    if (len == 4) {
        if (std.mem.eql(u8, basename, "true")) {
            return @import("true.zig").execute();
        }
    }
    if (len == 5) {
        if (std.mem.eql(u8, basename, "false")) {
            return @import("false.zig").execute();
        }
    }

    // TODO: Handle Error
    return 1;
}

comptime {
    std.testing.refAllDecls(@This());
}
