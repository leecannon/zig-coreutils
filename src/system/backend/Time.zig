// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const Time = @This();

source: Source,

pub inline fn nanoTimestamp(self: Time) i128 {
    return switch (self.source) {
        .host => std.time.nanoTimestamp(),
        .backend => |ptr| @atomicLoad(i128, ptr, .acquire),
    };
}

pub const Source = union(enum) {
    host,

    /// A pointer to the source to be used as the current time in nanoseconds.
    ///
    /// Reads are atomic with Acquire ordering.
    ///
    /// Note: This pointer must be valid for as long as the `TestBackend` exists.
    backend: *const i128,
};

const std = @import("std");
