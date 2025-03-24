// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const Uname = @This();

uname_source: System.Uname,

pub fn init(self: *Uname, description: UnameDescription) void {
    @memset(std.mem.asBytes(self), 0);

    if (description.sysname.len > self.uname_source.sysname.len) {
        @panic("UnameDescription.sysname is too long");
    }
    @memcpy(self.uname_source.sysname[0..description.sysname.len], description.sysname);

    if (description.nodename.len > self.uname_source.nodename.len) {
        @panic("UnameDescription.nodename is too long");
    }
    @memcpy(self.uname_source.nodename[0..description.nodename.len], description.nodename);

    if (description.release.len > self.uname_source.release.len) {
        @panic("UnameDescription.release is too long");
    }
    @memcpy(self.uname_source.release[0..description.release.len], description.release);

    if (description.version.len > self.uname_source.version.len) {
        @panic("UnameDescription.version is too long");
    }
    @memcpy(self.uname_source.version[0..description.version.len], description.version);

    if (description.machine.len > self.uname_source.machine.len) {
        @panic("UnameDescription.machine is too long");
    }
    @memcpy(self.uname_source.machine[0..description.machine.len], description.machine);

    if (description.domainname) |domainname| {
        if (domainname.len > self.uname_source.domainname.len) {
            @panic("UnameDescription.domainname is too long");
        }
        @memcpy(self.uname_source.domainname[0..domainname.len], domainname);
    } else {
        std.mem.copyForwards(u8, &self.uname_source.domainname, "(none)");
    }
}

pub inline fn uname(self: Uname) System.Uname {
    return self.uname_source;
}

pub const UnameDescription = struct {
    sysname: []const u8,
    nodename: []const u8,
    release: []const u8,
    version: []const u8,
    machine: []const u8,
    domainname: ?[]const u8,
};

const System = @import("../System.zig");

const std = @import("std");
