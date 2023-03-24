const std = @import("std");
const subcommands = @import("../subcommands.zig");
const shared = @import("../shared.zig");

const log = std.log.scoped(.nproc);
const mem = std.mem;
const fmt = std.fmt;

pub const name = "nproc";

pub const usage =
    \\Usage: {0s} [ignored command line arguments]
    \\   or: {0s} OPTION
    \\
    \\Print the number of processing units available.
    \\
    \\     -h, --help  display this help and exit
    \\     --version   output version information and exit
    \\
;

pub fn execute(
    allocator: std.mem.Allocator,
    io: anytype,
    args: anytype,
    cwd: std.fs.Dir,
    exe_path: []const u8,
) subcommands.Error!void {
    const z = shared.tracy.traceNamed(@src(), name);
    defer z.end();

    _ = exe_path;

    // Only the first argument is checked for help or version
    _ = try args.nextWithHelpOrVersion(true);

    const path = "/sys/devices/system/cpu/online";
    var buffer: [8]u8 = undefined;
    const file_contents = try shared.readFileIntoBuffer(@This(), allocator, io, cwd, path, &buffer);
    const nproc = 1 + (getLastCpuIndex(mem.trim(u8, file_contents, &std.ascii.whitespace)) catch {
        return shared.printError(
            @This(),
            io,
            "format of '" ++ path ++ "' is invalid: '{s}'",
        );
    });

    io.stdout.print("{}\n", .{nproc}) catch |err| {
        return shared.unableToWriteTo("stdout", io, err);
    };
}

fn getLastCpuIndex(str: []const u8) error{InvalidFormat}!usize {
    // Contains string like "0-3" listing the index range of the processors.
    var it = mem.split(u8, str, "-");
    // Also catches str.len == 0.
    if (it.next() == null) return error.InvalidFormat;
    const last_index_str = it.next() orelse return error.InvalidFormat;
    const last_index = fmt.parseInt(usize, last_index_str, 10) catch return error.InvalidFormat;
    if (it.next() != null) return error.InvalidFormat;
    return last_index;
}

test "nproc getLastCpuIndex()" {
    const testing = std.testing;
    const valid_input = "0-3";
    try testing.expect(try getLastCpuIndex(valid_input) == 3);
    const invalid_input_a = "0-";
    try testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_a));
    const invalid_input_b = "0";
    try testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_b));
    const invalid_input_c = "0-4-5";
    try testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_c));
    const invalid_input_d = "invalid";
    try testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_d));
    const invalid_input_e = "";
    try testing.expectError(error.InvalidFormat, getLastCpuIndex(invalid_input_e));
}

test "nproc help" {
    try subcommands.testHelp(@This(), true);
}

test "nproc version" {
    try subcommands.testVersion(@This());
}

comptime {
    refAllDeclsRecursive(@This());
}

/// This is a copy of `std.testing.refAllDeclsRecursive` but as it is in the file it can access private decls
/// Also it only reference structs, enums, unions, opaques, types and functions
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (decl.is_pub) {
            if (@TypeOf(@field(T, decl.name)) == type) {
                switch (@typeInfo(@field(T, decl.name))) {
                    .Struct, .Enum, .Union, .Opaque => {
                        refAllDeclsRecursive(@field(T, decl.name));
                        _ = @field(T, decl.name);
                    },
                    .Type, .Fn => {
                        _ = @field(T, decl.name);
                    },
                    else => {},
                }
            }
        }
    }
}
