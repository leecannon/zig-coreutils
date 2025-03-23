// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const TestBackend = @This();

allocator: std.mem.Allocator,

time: Time,
file_system: ?FileSystem,
user_group: ?UserGroup,

pub fn create(allocator: std.mem.Allocator, description: Description) !*TestBackend {
    const self = try allocator.create(TestBackend);
    errdefer allocator.destroy(self);

    self.* = .{
        .allocator = allocator,
        .time = .{ .source = description.time },
        .file_system = null,
        .user_group = null,
    };

    if (description.user_group) |ug_description| {
        self.user_group = @as(UserGroup, undefined);
        self.user_group.?.init(ug_description);
    }

    if (description.file_system) |fs_description| {
        self.file_system = @as(FileSystem, undefined);
        try self.file_system.?.init(self, fs_description);
    }

    return self;
}

pub fn destroy(self: *TestBackend) void {
    if (self.file_system) |*fs| fs.deinit();
    self.allocator.destroy(self);
}

pub const Description = @import("Description.zig");

pub const FileSystem = @import("FileSystem.zig");
const Time = @import("Time.zig");
const UserGroup = @import("UserGroup.zig");
const System = @import("../System.zig");

const log = std.log.scoped(.system_test_backend);

const is_test = @import("builtin").is_test;
const target_os = @import("target_os").target_os;
const std = @import("std");
const tracy = @import("tracy");
