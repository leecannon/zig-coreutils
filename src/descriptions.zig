const std = @import("std");
const Context = @import("Context.zig");

pub const DESCRIPTIONS = [_]Description{
    @import("false.zig").description,
    @import("true.zig").description,
};

pub fn executeSubcommand(context: Context, basename: []const u8) ?u8 {
    comptime var len = 1;
    inline while (len <= longest_description_name) : (len += 1) {
        inline for (comptime getDescriptionsWithNameLength(len)) |desc| {
            if (std.mem.eql(u8, desc.name, basename)) return desc.execute(context);
        }
    }
    return null;
}

pub const Description = struct {
    name: []const u8,
    usage: []const u8,
    execute: fn (Context) u8,
};

fn getDescriptionsWithNameLength(comptime len: comptime_int) [numberOfDescriptionsWithNameLength(len)]Description {
    comptime var descriptions: [numberOfDescriptionsWithNameLength(len)]Description = undefined;
    comptime var i = 0;

    inline for (DESCRIPTIONS) |desc| {
        if (desc.name.len == len) {
            descriptions[i] = desc;
            i += 1;
        }
    }
    return descriptions;
}

fn numberOfDescriptionsWithNameLength(comptime len: comptime_int) comptime_int {
    comptime var i = 0;
    inline for (DESCRIPTIONS) |desc| {
        if (desc.name.len == len) i += 1;
    }
    return i;
}

const longest_description_name = blk: {
    comptime var i = 0;
    inline for (DESCRIPTIONS) |desc| {
        if (desc.name.len > i) i = desc.name.len;
    }
    break :blk i;
};

comptime {
    std.testing.refAllDecls(@This());
}
