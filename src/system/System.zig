// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

//! Proivides a platform-agnostic interface to the system.
//!
//! During tests automatically uses a mock implementation.

const System = @This();

_backend: if (is_test) *TestBackend else void = if (is_test) undefined else {},

/// Get a calendar timestamp, in nanoseconds, relative to UTC 1970-01-01.
pub inline fn nanoTimestamp(self: System) i128 {
    if (is_test) {
        return self._backend.time.nanoTimestamp();
    }

    return std.time.nanoTimestamp();
}

/// Returns a handle to the current working directory.
pub inline fn cwd(system: System) Dir {
    if (is_test) {
        if (system._backend.file_system) |*file_system| {
            return .{ ._data = .{
                .file_system = file_system,
                .ptr = TestBackend.FileSystem.CWD,
            } };
        }

        @panic("`cwd` called with no file system configured");
    }

    return .{ ._data = std.fs.cwd() };
}

pub inline fn getEffectiveUserId(system: System) UserId {
    if (is_test) {
        if (system._backend.user_group) |user_group| {
            return user_group.getEffectiveUserId();
        }

        @panic("`getEffectiveUserId` called with no user/group configured");
    }

    return switch (target_os) {
        .linux => std.os.linux.getuid(),
        .macos => {
            const c = struct {
                pub extern "c" fn geteuid() std.c.uid_t;
            };
            return c.geteuid();
        },
        .windows => @panic("getUserId not implemented for windows"), // FIXME: support windows
    };
}

pub const UserId = blk: {
    if (is_test) break :blk u32;
    break :blk switch (target_os) {
        .linux => std.os.linux.uid_t,
        .macos => std.c.uid_t,
        .windows => noreturn, // FIXME: support windows
    };
};

pub const Dir = struct {
    _data: Data,

    /// Opens a file relative to the directory without creating it.
    pub inline fn openFile(self: Dir, sub_path: []const u8, options: File.OpenOptions) !File {
        if (is_test) {
            return .{ ._data = .{
                .file_system = self._data.file_system,
                .ptr = try self._data.file_system.openFileFromDir(
                    self._data.ptr,
                    sub_path,
                    options,
                ),
            } };
        }

        return .{ ._data = try self._data.openFile(sub_path, options.toStd()) };
    }

    /// Opens a file relative to the directory, creates it if it does not exist.
    pub inline fn createFile(self: Dir, sub_path: []const u8, options: File.CreateOptions) !File {
        if (is_test) {
            return .{ ._data = .{
                .file_system = self._data.file_system,
                .ptr = try self._data.file_system.createFileFromDir(
                    self._data.ptr,
                    sub_path,
                    options,
                ),
            } };
        }

        return .{ ._data = try self._data.createFile(sub_path, options.toStd()) };
    }

    const Data = if (is_test) struct {
        file_system: *TestBackend.FileSystem,
        ptr: *anyopaque,
    } else std.fs.Dir;
};

pub const File = struct {
    _data: Data,

    /// Close the file and deallocate any related resources.
    pub inline fn close(self: File) void {
        if (is_test) {
            self._data.file_system.closeFile(self._data.ptr);
            return;
        }

        self._data.close();
    }

    /// Reads up to `buffer.len` bytes from the file into `buffer`.
    ///
    /// Returns the number of bytes read.
    ///
    /// If the number read is smaller than `buffer.len`, it means the file reached the end.
    pub inline fn readAll(self: File, buffer: []u8) !usize {
        if (is_test) {
            return try self._data.file_system.readAllFromFile(self._data.ptr, buffer);
        }

        return self._data.readAll(buffer);
    }

    pub const Stat = struct {
        size: u64,

        atime: i128,
        mtime: i128,
    };

    /// Returns basic information about the file.
    pub inline fn stat(self: File) !Stat {
        if (is_test) {
            return self._data.file_system.statFile(self._data.ptr);
        }

        const s = try self._data.stat();

        return .{
            .size = s.size,
            .atime = s.atime,
            .mtime = s.mtime,
        };
    }

    pub fn mapReadonly(self: File, size: u64) !FileMap {
        if (size == 0) {
            @branchHint(.unlikely);
            return .{
                ._data = undefined,
                .file_contents = &.{},
            };
        }

        if (is_test) {
            return try self._data.file_system.mapFileReadonly(self._data.ptr, size);
        }

        const file_contents = switch (target_os) {
            .linux, .macos => try std.posix.mmap(
                null,
                size,
                std.posix.PROT.READ,
                .{ .TYPE = .PRIVATE },
                self._data.handle,
                0,
            ),
            .windows => @panic("mapReadonly not implemented for windows"), // FIXME: support windows
        };

        return .{
            ._data = self._data,
            .file_contents = file_contents,
        };
    }

    pub fn updateTimes(self: File, access_time: i128, modification_time: i128) !void {
        if (is_test) {
            return self._data.file_system.updateTimes(self._data.ptr, access_time, modification_time);
        }

        return try self._data.updateTimes(access_time, modification_time);
    }

    pub const OpenOptions = struct {
        mode: std.fs.File.OpenMode = .read_only,

        inline fn toStd(options: OpenOptions) std.fs.File.OpenFlags {
            return .{
                .mode = options.mode,
            };
        }
    };

    pub const CreateOptions = struct {
        /// Whether the file will be created with read access.
        read: bool = false,

        /// If the file already exists, and is a regular file, and the access
        /// mode allows writing, it will be truncated to length 0.
        truncate: bool = true,

        inline fn toStd(options: CreateOptions) std.fs.File.CreateFlags {
            return .{
                .read = options.read,
                .truncate = options.truncate,
            };
        }
    };

    const Data = if (is_test) struct {
        file_system: *TestBackend.FileSystem,
        ptr: *anyopaque,
    } else std.fs.File;
};

pub const FileMap = struct {
    _data: Data,
    file_contents: []align(std.heap.page_size_min) const u8,

    pub fn close(self: FileMap) void {
        if (shared.free_on_close) {
            if (self.file_contents.len == 0) {
                @branchHint(.unlikely);
                return;
            }

            if (is_test) {
                self._data.file_system.closeFileMap(self._data.ptr);
                return;
            }

            switch (target_os) {
                .linux, .macos => std.posix.munmap(self.file_contents),
                .windows => @panic("FileMap.close not implemented for windows"), // FIXME: support windows
            }
        }
    }

    const Data = if (is_test) struct {
        file_system: *TestBackend.FileSystem,
        ptr: *anyopaque,
    } else std.fs.File;
};

pub const TestBackend = @import("backend/TestBackend.zig");

const log = std.log.scoped(.system);

const is_test = @import("builtin").is_test;
const target_os = @import("target_os").target_os;
const std = @import("std");
const shared = @import("../shared.zig");
