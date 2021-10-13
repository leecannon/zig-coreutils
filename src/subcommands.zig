const std = @import("std");
const Context = @import("Context.zig");

pub const SUBCOMMANDS = [_]Subcommand{
    @import("subcommands/false.zig").subcommand,
    @import("subcommands/true.zig").subcommand,
};

pub fn executeSubcommand(context: *Context, basename: []const u8) !u8 {
    comptime var len = 1;
    inline while (len <= longest_subcommand_name) : (len += 1) {
        inline for (comptime getSubcommandsWithNameLength(len)) |desc| {
            if (std.mem.eql(u8, desc.name, basename)) return desc.execute(context);
        }
    }
    return error.NoSubcommand;
}

pub const Subcommand = struct {
    name: []const u8,
    usage: []const u8,
    execute: fn (*Context) Error!u8,

    pub const Error = error{
        OutOfMemory,
        InvalidCmdLine,
        HelpOrVersion,
    };
};

fn getSubcommandsWithNameLength(comptime len: comptime_int) [numberOfSubcommandsWithNameLength(len)]Subcommand {
    comptime var subcommands: [numberOfSubcommandsWithNameLength(len)]Subcommand = undefined;
    comptime var i = 0;

    inline for (SUBCOMMANDS) |desc| {
        if (desc.name.len == len) {
            subcommands[i] = desc;
            i += 1;
        }
    }
    return subcommands;
}

fn numberOfSubcommandsWithNameLength(comptime len: comptime_int) comptime_int {
    comptime var i = 0;
    inline for (SUBCOMMANDS) |desc| {
        if (desc.name.len == len) i += 1;
    }
    return i;
}

const longest_subcommand_name = blk: {
    comptime var i = 0;
    inline for (SUBCOMMANDS) |desc| {
        if (desc.name.len > i) i = desc.name.len;
    }
    break :blk i;
};

comptime {
    std.testing.refAllDecls(@This());
}
