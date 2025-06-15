// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

/// Alphabetically sorted list of all commands.
pub const commands: []const type = &.{
    @import("basename.zig"),
    @import("clear.zig"),
    @import("dirname.zig"),
    @import("false.zig"),
    @import("groups.zig"),
    @import("nproc.zig"),
    @import("touch.zig"),
    @import("true.zig"),
    @import("uname.zig"),
    @import("unlink.zig"),
    @import("whoami.zig"),
    @import("yes.zig"),
};
