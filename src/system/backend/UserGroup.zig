// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const UserGroup = @This();

effective_user_id: System.UserId,

pub fn init(self: *UserGroup, description: UserGroupDescription) void {
    self.* = .{
        .effective_user_id = description.effective_user_id,
    };
}

pub fn getEffectiveUserId(self: UserGroup) System.UserId {
    return self.effective_user_id;
}

pub const UserGroupDescription = struct {
    effective_user_id: System.UserId,
};

const System = @import("../System.zig");
const std = @import("std");
