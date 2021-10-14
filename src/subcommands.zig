const std = @import("std");
const Context = @import("Context.zig");
const args = @import("args");

pub const SUBCOMMANDS = [_]type{
    @import("subcommands/false.zig"),
    @import("subcommands/true.zig"),
};

pub fn executeSubcommand(context: *Context, basename: []const u8, arg_iter: *std.process.ArgIterator) !u8 {
    inline for (SUBCOMMANDS) |subcommand| {
        if (std.mem.eql(u8, subcommand.name, basename)) return execute(subcommand, context, arg_iter);
    }

    return error.NoSubcommand;
}

fn execute(comptime subcommand: type, context: *Context, arg_iter: *std.process.ArgIterator) !u8 {
    var errors = args.ErrorCollection.init(context.allocator);
    defer errors.deinit();

    const options = args.parse(subcommand.options_def, arg_iter, context.allocator, .{ .collect = &errors }) catch |err| {
        if (err == error.InvalidArguments) {
            // TODO: print error and usage
            // std.log.info("{any}", .{errors.errors()});
            return @as(u8, 1);
        }

        return error.FailedToParseArguments;
    };
    defer options.deinit();

    if (options.options.help) {
        context.out().print(subcommand.usage, .{context.exe_path}) catch {};
        return error.HelpOrVersion;
    }
    if (options.options.version) {
        context.printVersion(subcommand.name);
        return error.HelpOrVersion;
    }

    return subcommand.execute(context, options);
}

pub const Error = error{
    OutOfMemory,
};

comptime {
    std.testing.refAllDecls(@This());
}
