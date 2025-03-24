// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

time: TimeSource = .host,
file_system: ?*FileSystemDescription = null,
user_group: ?UserGroupDescription = null,
uname: ?UnameDescription = null,

pub const FileSystemDescription = @import("FileSystem.zig").FileSystemDescription;
pub const TimeSource = @import("Time.zig").Source;
pub const UserGroupDescription = @import("UserGroup.zig").UserGroupDescription;
pub const UnameDescription = @import("Uname.zig").UnameDescription;
