// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

pub const base_version_string = "zig-coreutils " ++ options.version ++ "\nMIT License Copyright (c) 2025 Lee Cannon\n";
pub const version_string = "{NAME} - " ++ base_version_string;
pub const is_debug_or_test = builtin.is_test or builtin.mode == .Debug;
pub const free_on_close = is_debug_or_test or options.trace;

pub fn mapFile(
    command: Command,
    allocator: std.mem.Allocator,
    io: IO,
    cwd: std.fs.Dir,
    path: []const u8,
) error{ AlreadyHandled, OutOfMemory }!MappedFile {
    const file = cwd.openFile(path, .{}) catch
        return command.printErrorAlloc(
            allocator,
            io,
            "unable to open '{s}'",
            .{path},
        );
    errdefer if (free_on_close) file.close();

    const stat = file.stat() catch |err|
        return command.printErrorAlloc(
            allocator,
            io,
            "unable to stat '{s}': {s}",
            .{ path, @errorName(err) },
        );

    if (stat.size == 0) {
        @branchHint(.unlikely);
        return .{
            .file = file,
            .file_contents = &.{},
        };
    }

    const file_contents = std.posix.mmap(
        null,
        stat.size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    ) catch |err|
        return command.printErrorAlloc(
            allocator,
            io,
            "unable to map '{s}': {s}",
            .{ path, @errorName(err) },
        );

    return .{
        .file = file,
        .file_contents = file_contents,
    };
}

pub const MappedFile = struct {
    file: std.fs.File,
    file_contents: []align(std.heap.page_size_min) const u8,

    pub fn close(self: MappedFile) void {
        if (free_on_close) {
            if (self.file_contents.len != 0) {
                @branchHint(.likely);
                std.posix.munmap(self.file_contents);
            }
            self.file.close();
        }
    }
};

pub fn readFileIntoBuffer(
    command: Command,
    allocator: std.mem.Allocator,
    io: IO,
    cwd: std.fs.Dir,
    path: []const u8,
    buffer: []u8,
) error{ AlreadyHandled, OutOfMemory }![]const u8 {
    const file = cwd.openFile(path, .{}) catch
        return command.printErrorAlloc(
            allocator,
            io,
            "unable to open '{s}'",
            .{path},
        );
    defer if (free_on_close) file.close();

    const reader = file.reader();
    const read = reader.readAll(buffer) catch |err|
        return command.printErrorAlloc(
            allocator,
            io,
            "unable to read file '{s}': {s}",
            .{ path, @errorName(err) },
        );

    return buffer[0..read];
}

pub fn passwdFileIterator(passwd_file_contents: []const u8) PasswdFileIterator {
    return .{
        .passwd_file_contents = passwd_file_contents,
    };
}

pub const PasswdFileIterator = struct {
    index: usize = 0,
    passwd_file_contents: []const u8,

    pub const Entry = struct {
        user_name: []const u8,
        user_id: []const u8,
        primary_group_id: []const u8,
    };

    /// The returned `Entry` is invalidated on any subsequent call to `next`
    pub fn next(
        self: *PasswdFileIterator,
        command: Command,
        io: IO,
    ) error{AlreadyHandled}!?Entry {
        if (self.index >= self.passwd_file_contents.len) {
            @branchHint(.unlikely);
            return null;
        }

        const remaining = self.passwd_file_contents[self.index..];

        const line_length =
            std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len - 1;

        self.index += line_length + 1;

        var column_iter = std.mem.tokenizeScalar(
            u8,
            remaining[0..line_length],
            ':',
        );

        const user_name = column_iter.next() orelse
            return command.printError(io, "format of '/etc/passwd' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return command.printError(io, "format of '/etc/passwd' is invalid");

        const user_id_slice = column_iter.next() orelse
            return command.printError(io, "format of '/etc/passwd' is invalid");

        const primary_group_id_slice = column_iter.next() orelse
            return command.printError(io, "format of '/etc/passwd' is invalid");

        return .{
            .user_name = user_name,
            .user_id = user_id_slice,
            .primary_group_id = primary_group_id_slice,
        };
    }
};

pub fn groupFileIterator(group_file_contents: []const u8) GroupFileIterator {
    return .{
        .group_file_contents = group_file_contents,
    };
}

pub const GroupFileIterator = struct {
    index: usize = 0,
    group_file_contents: []const u8,

    pub const Entry = struct {
        group_name: []const u8,
        group_id: []const u8,
        members_slice: ?[]const u8,

        pub fn iterateMembers(self: *const Entry) std.mem.TokenIterator(u8, .scalar) {
            return std.mem.tokenizeScalar(u8, self.members_slice orelse &[_]u8{}, ',');
        }
    };

    /// The returned `Entry` is invalidated on any subsequent call to `next`
    pub fn next(
        self: *GroupFileIterator,
        command: Command,
        io: IO,
    ) error{AlreadyHandled}!?Entry {
        if (self.index >= self.group_file_contents.len) {
            @branchHint(.unlikely);
            return null;
        }

        const remaining = self.group_file_contents[self.index..];

        const line_length =
            std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len - 1;

        self.index += line_length + 1;

        var column_iter = std.mem.tokenizeScalar(
            u8,
            remaining[0..line_length],
            ':',
        );

        const group_name = column_iter.next() orelse
            return command.printError(io, "format of '/etc/group' is invalid");

        // skip password stand-in
        _ = column_iter.next() orelse
            return command.printError(io, "format of '/etc/group' is invalid");

        const group_id_slice = column_iter.next() orelse
            return command.printError(io, "format of '/etc/group' is invalid");

        return .{
            .group_name = group_name,
            .group_id = group_id_slice,
            .members_slice = column_iter.next(),
        };
    }
};

pub const MaybeAllocatedString = MaybeAllocated(
    []const u8,
    struct {
        fn freeSlice(self: []const u8, allocator: std.mem.Allocator) void {
            allocator.free(self);
        }
    }.freeSlice,
);

pub fn MaybeAllocated(comptime T: type, comptime dealloc: fn (self: T, allocator: std.mem.Allocator) void) type {
    return struct {
        is_allocated: bool,
        value: T,

        pub fn allocated(value: T) @This() {
            return .{
                .is_allocated = true,
                .value = value,
            };
        }

        pub fn not_allocated(value: T) @This() {
            return .{
                .is_allocated = false,
                .value = value,
            };
        }

        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            if (self.is_allocated) {
                dealloc(self.value, allocator);
            }
        }
    };
}

pub const VoidReader = struct {
    pub const Reader = std.io.Reader(void, error{}, read);
    pub fn reader() Reader {
        return .{ .context = {} };
    }

    fn read(_: void, buffer: []u8) error{}!usize {
        _ = buffer;
        return 0;
    }
};

pub const VoidWriter = struct {
    pub const Writer = std.io.Writer(void, error{}, write);
    pub fn writer() Writer {
        return .{ .context = {} };
    }

    fn write(_: void, bytes: []const u8) error{}!usize {
        return bytes.len;
    }
};

const Command = @import("Command.zig");
const IO = @import("IO.zig");

const log = std.log.scoped(.shared);

const builtin = @import("builtin");
const options = @import("options");
const std = @import("std");
const tracy = @import("tracy");

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
