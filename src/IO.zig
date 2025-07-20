// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const IO = @This();

_stdin: *std.Io.Reader,
_stdout: *std.Io.Writer,
_stderr: *std.Io.Writer,

pub inline fn stdoutWriteByte(io: IO, byte: u8) error{AlreadyHandled}!void {
    io._stdout.writeByte(byte) catch |err| {
        @branchHint(.cold);
        return io.unableToWriteTo("stdout", err);
    };
}

pub inline fn stdoutWriteAll(io: IO, bytes: []const u8) error{AlreadyHandled}!void {
    io._stdout.writeAll(bytes) catch |err| {
        @branchHint(.cold);
        return io.unableToWriteTo("stdout", err);
    };
}

pub inline fn stdoutPrint(io: IO, comptime fmt: []const u8, args: anytype) error{AlreadyHandled}!void {
    io._stdout.print(fmt, args) catch |err| {
        @branchHint(.cold);
        return io.unableToWriteTo("stdout", err);
    };
}

pub fn unableToWriteTo(io: IO, destination: []const u8, err: anyerror) error{AlreadyHandled} {
    @branchHint(.cold);

    blk: {
        io._stderr.writeAll("unable to write to ") catch {
            @branchHint(.cold);
            break :blk;
        };
        io._stderr.writeAll(destination) catch {
            @branchHint(.cold);
            break :blk;
        };
        io._stderr.writeAll(": ") catch {
            @branchHint(.cold);
            break :blk;
        };
        io._stderr.writeAll(@errorName(err)) catch {
            @branchHint(.cold);
            break :blk;
        };
        io._stderr.writeByte('\n') catch {
            @branchHint(.cold);
            break :blk;
        };
    }

    return error.AlreadyHandled;
}

const std = @import("std");
