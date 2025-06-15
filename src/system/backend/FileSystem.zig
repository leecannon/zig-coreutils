// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2025 Lee Cannon <leecannon@leecannon.xyz>

const FileSystem = @This();

backend: *TestBackend,

entries: std.AutoHashMapUnmanaged(*Entry, void),
views: std.AutoHashMapUnmanaged(*View, void),

root: *Entry,
cwd_entry: *Entry,

pub fn init(self: *FileSystem, backend: *TestBackend, description: *const FileSystemDescription) !void {
    self.* = .{
        .backend = backend,
        .entries = .empty,
        .views = .empty,
        .root = undefined,
        .cwd_entry = undefined,
    };

    try self.entries.ensureTotalCapacity(backend.allocator, @intCast(description.entries.items.len));

    var opt_root: ?*Entry = null;
    var opt_cwd_entry: ?*Entry = null;

    _ = try self.initAddDirAndRecurse(
        description,
        &description.root,
        description.cwd,
        &opt_root,
        &opt_cwd_entry,
        backend.time.nanoTimestamp(),
    );

    if (opt_root) |root| {
        self.root = root;
        self.root.incrementReference();
    } else return error.NoRootDirectory;

    if (opt_cwd_entry) |cwd_entry| {
        try self.setCwd(cwd_entry, false);
    } else return error.NoCwd;
}

fn initAddDirAndRecurse(
    self: *FileSystem,
    description: *const FileSystemDescription,
    current_dir: *const FileSystemDescription.EntryDescription,
    ptr_to_inital_cwd: *const FileSystemDescription.EntryDescription,
    opt_root: *?*Entry,
    opt_cwd_entry: *?*Entry,
    current_time: i128,
) (error{DuplicateEntry} || std.mem.Allocator.Error)!*Entry {
    std.debug.assert(current_dir.subdata == .dir);

    const dir_entry = try self.addDirEntry(current_dir.name, current_time);

    if (opt_root.* == null) opt_root.* = dir_entry;
    if (opt_cwd_entry.* == null and current_dir == ptr_to_inital_cwd) opt_cwd_entry.* = dir_entry;

    for (current_dir.subdata.dir.entries.values()) |entry| {
        const new_entry: *Entry = switch (entry.subdata) {
            .file => |file| try self.addFileEntry(entry.name, file.contents, current_time),
            .dir => try self.initAddDirAndRecurse(
                description,
                entry,
                ptr_to_inital_cwd,
                opt_root,
                opt_cwd_entry,
                current_time,
            ),
        };

        try dir_entry.addEntry(new_entry, current_time);
    }

    return dir_entry;
}

pub fn deinit(self: *FileSystem) void {
    var view_iter = self.views.keyIterator();
    while (view_iter.next()) |view| view.*.destroy();
    self.views.deinit(self.backend.allocator);

    var entries_iter = self.entries.keyIterator();
    while (entries_iter.next()) |entry| entry.*.destroy();
    self.entries.deinit(self.backend.allocator);
}

pub const CWD: *anyopaque = @ptrFromInt(std.mem.alignBackward(
    usize,
    std.math.maxInt(usize),
    @alignOf(View),
));

pub const OpenFileError = error{
    FileNotFound,
    /// The path resolves to a directory.
    IsDirectory,
    /// The systems resources were exhausted.
    SystemResources,
} || PathError || ResolveEntryError;

/// Opens a file relative to the directory without creating it.
pub fn openFile(
    self: *FileSystem,
    ptr: *anyopaque,
    sub_path: []const u8,
    options: System.File.OpenOptions,
) OpenFileError!*anyopaque {
    if (target_os == .windows) {
        // TODO: implement windows
        @panic("Windows support is unimplemented");
    }

    if (options.mode != .read_only) {
        // TODO: Implement *not* read_only
        std.debug.panic("file mode '{s}' is unimplemented", .{@tagName(options.mode)});
    }

    const dir_entry = self.cwdOrEntry(ptr) orelse unreachable; // no such directory
    std.debug.assert(dir_entry.subdata == .dir);

    const path = try self.toPath(dir_entry, sub_path);

    const entry = (try self.resolveEntry(path, null)) orelse {
        @branchHint(.cold);
        return error.FileNotFound;
    };
    if (entry.subdata != .file) {
        @branchHint(.cold);
        return error.IsDirectory;
    }

    const view = self.addView(entry) catch {
        @branchHint(.cold);
        return error.SystemResources;
    };

    return view;
}

/// Opens a file relative to the directory, creates it if it does not exist.
pub fn createFile(
    self: *FileSystem,
    ptr: *anyopaque,
    user_path: []const u8,
    flags: System.File.CreateOptions,
) OpenFileError!*anyopaque {
    if (target_os == .windows) {
        // TODO: implement windows
        @panic("Windows support is unimplemented");
    }

    // TODO: implement support for flags.mode
    // TODO: implement support for flags.read

    const dir_entry = self.cwdOrEntry(ptr) orelse unreachable; // no such directory
    std.debug.assert(dir_entry.subdata == .dir);

    const path = try self.toPath(dir_entry, user_path);

    const entry = blk: {
        var expected_parent: *Entry = undefined;

        const entry = (try self.resolveEntry(path, &expected_parent)) orelse {
            // file doesn't exist

            const basename = std.fs.path.basename(path.path);
            const current_time = self.backend.time.nanoTimestamp();

            const file = self.addFileEntry(
                basename,
                "",
                current_time,
            ) catch {
                @branchHint(.cold);
                return error.SystemResources;
            };
            errdefer {
                _ = self.entries.remove(file);
                file.destroy();
            }

            expected_parent.addEntry(
                file,
                current_time,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.SystemResources,
                error.DuplicateEntry => unreachable, // the entry was not found so this is impossible
            };

            break :blk file;
        };

        // file already exists

        if (entry.subdata != .file) {
            @branchHint(.cold);
            return error.IsDirectory;
        }

        if (flags.truncate) {
            // TODO: check mode
            // TODO: should this free the contents?
            entry.subdata.file.contents.items.len = 0;
        }

        break :blk entry;
    };

    return self.addView(entry) catch {
        @branchHint(.cold);
        return error.SystemResources;
    };
}

/// Reads up to `buffer.len` bytes from the file into `buffer`.
///
/// Returns the number of bytes read.
///
/// If the number read is smaller than `buffer.len`, it means the file reached the end.
pub fn readAllFile(self: *FileSystem, ptr: *anyopaque, buffer: []u8) usize {
    const view = self.toView(ptr) orelse unreachable; // no such file

    const entry = view.entry;

    switch (entry.subdata) {
        .dir => unreachable,
        .file => |file| {
            const slice = file.contents.items;

            const size = @min(buffer.len, slice.len - view.position);

            @memcpy(buffer[0..size], slice[view.position..][0..size]);

            view.position += size;

            entry.atime = self.backend.time.nanoTimestamp();

            return size;
        },
    }
}

pub fn statFile(self: *FileSystem, ptr: *anyopaque) System.File.Stat {
    const view = self.toView(ptr) orelse unreachable; // no such file

    switch (view.entry.subdata) {
        .dir => unreachable,
        .file => |f| {
            return .{
                .size = f.contents.items.len,
                .atime = view.entry.atime,
                .mtime = view.entry.mtime,
            };
        },
    }
}

/// Provide the file contents as a read-only "memory map".
pub fn mapFileReadonly(self: *FileSystem, ptr: *anyopaque, size: usize) System.FileMap {
    const view = self.toView(ptr) orelse unreachable; // no such file

    switch (view.entry.subdata) {
        .dir => unreachable,
        .file => |f| {
            view.entry.incrementReference();
            return .{
                ._data = .{
                    .file_system = self,
                    .ptr = view.entry,
                },
                .file_contents = f.contents.items[0..size],
            };
        },
    }
}

pub fn closeFileMap(self: *FileSystem, ptr: *anyopaque) void {
    const entry: *Entry = self.toEntry(ptr) orelse unreachable; // no such file
    std.debug.assert(entry.subdata == .file);
    _ = entry.decrementReference();
}

pub fn closeFile(self: *FileSystem, ptr: *anyopaque) void {
    const view = self.toView(ptr) orelse unreachable; // no such file
    std.debug.assert(view.entry.subdata == .file);
    _ = view.entry.decrementReference();
    _ = self.views.remove(view);
    view.destroy();
}

/// Update the access and modification times of the file or directory.
pub fn updateTimes(self: *FileSystem, ptr: *anyopaque, access_time: i128, modification_time: i128) !void {
    const view = self.toView(ptr) orelse unreachable; // no such file or directory
    view.entry.atime = access_time;
    view.entry.mtime = modification_time;
}

/// Create a file entry and add it to the `entries` hash map.
fn addFileEntry(self: *FileSystem, name: []const u8, contents: []const u8, current_time: i128) !*Entry {
    const entry = try Entry.createFile(self, name, contents, current_time);
    errdefer entry.destroy();

    try self.entries.putNoClobber(self.backend.allocator, entry, {});

    return entry;
}

/// Create a dir entry and add it to the `entries` hash map.
fn addDirEntry(self: *FileSystem, name: []const u8, current_time: i128) !*Entry {
    const entry = try Entry.createDir(self, name, current_time);
    errdefer entry.destroy();

    try self.entries.putNoClobber(self.backend.allocator, entry, {});

    return entry;
}

/// Add a view to the given entry.
fn addView(self: *FileSystem, entry: *Entry) !*View {
    entry.incrementReference();
    errdefer _ = entry.decrementReference();

    const view = try self.backend.allocator.create(View);
    errdefer self.backend.allocator.destroy(view);

    view.* = .{
        .entry = entry,
        .file_system = self,
    };

    try self.views.putNoClobber(self.backend.allocator, view, {});

    return view;
}

/// Set the current working directory.
fn setCwd(self: *FileSystem, entry: *Entry, dereference_old_cwd: bool) !void {
    entry.incrementReference();
    if (dereference_old_cwd) _ = self.cwd_entry.decrementReference();
    self.cwd_entry = entry;
}

/// Check if the given pointer is the current working directory.
inline fn isCwd(ptr: *anyopaque) bool {
    return CWD == ptr;
}

/// Cast the given `ptr` to an entry if it is one.
inline fn toEntry(self: *FileSystem, ptr: *anyopaque) ?*Entry {
    const entry: *Entry = @ptrCast(@alignCast(ptr));
    if (self.entries.contains(entry)) {
        @branchHint(.likely);
        return entry;
    }
    return null;
}

/// Cast the given `ptr` to a view if it is one.
inline fn toView(self: *FileSystem, ptr: *anyopaque) ?*View {
    const view: *View = @ptrCast(@alignCast(ptr));
    if (self.views.contains(view)) {
        @branchHint(.likely);
        return view;
    }
    return null;
}

const PathError = error{BadPath};

/// Construct a `Path` from the given string and the possible parent.
///
/// The `search_root` will be the root directory if the path is absolute, otherwise it will be the given parent.
///
/// The possible parent must be a directory entry.
fn toPath(self: *FileSystem, possible_parent: *Entry, str: []const u8) PathError!Path {
    std.debug.assert(possible_parent.subdata == .dir);
    if (str.len == 0) {
        @branchHint(.cold);
        return error.BadPath;
    }
    return .{
        .path = str,
        .search_root = if (std.fs.path.isAbsolute(str)) self.root else possible_parent,
    };
}

/// Return the entry associated with the given view, if there is one.
fn cwdOrEntry(self: *FileSystem, ptr: *anyopaque) ?*Entry {
    if (isCwd(ptr)) return self.cwd_entry;
    if (self.toView(ptr)) |v| {
        @branchHint(.likely);
        return v.entry;
    }
    return null;
}

const ResolveEntryError = error{
    /// A non-existent directory was encountered while traversing the path.
    DirectoryNotFound,
    /// A file was encountered while traversing the path.
    NotDirectory,
};

/// Searches from the path's search root for the entry specified by the given path, returns null only if only the last
/// section of the path is not found.
///
/// If the `expected_parent` parameter is non-null and the function returns null (as specified in the first paragraph)
/// then the parent that was expected to hold the target entry is written to the `expected_parent` pointer.
fn resolveEntry(self: *FileSystem, path: Path, expected_parent: ?**Entry) ResolveEntryError!?*Entry {
    var entry: *Entry = path.search_root;
    std.debug.assert(entry.subdata == .dir);

    var path_iter = std.mem.tokenizeScalar(u8, path.path, std.fs.path.sep);
    while (path_iter.next()) |path_section| {
        if (path_section.len == 0) {
            @branchHint(.unlikely);
            // empty path sections are ignored
            continue;
        }

        // handle '.' and '..'
        if (path_section[0] == '.') {
            switch (path_section.len) {
                // '.' leaves the entry unchanged
                1 => continue,
                // '..' traverses to the parent directory
                2 => if (path_section[1] == '.') {
                    if (entry.parent) |entry_parent| {
                        @branchHint(.likely);
                        entry = entry_parent;
                        continue;
                    }

                    if (entry == self.root) {
                        @branchHint(.likely);
                        // "/.." resolves to the root directory
                        continue;
                    }

                    @panic("non-root directory has no parent");
                },
                else => {},
            }
        }

        const child = entry.subdata.dir.entries.get(path_section) orelse {
            if (path_iter.next() != null) {
                // missing directory encountered in middle of path
                @branchHint(.cold);
                return error.DirectoryNotFound;
            }
            if (expected_parent) |parent| {
                parent.* = entry;
            }
            return null;
        };

        switch (child.subdata) {
            .dir => entry = child,
            .file => {
                if (path_iter.next() != null) {
                    @branchHint(.cold);
                    // file encountered in middle of path
                    return error.NotDirectory;
                }
                return child;
            },
        }
    }

    return entry;
}

const Entry = struct {
    ref_count: usize = 0,

    name: []const u8,
    subdata: SubData,

    parent: ?*Entry = null,

    /// time of last access
    atime: i128 = 0,
    /// time of last modification
    mtime: i128 = 0,
    /// time of last status change
    ctime: i128 = 0,

    // TODO: implement permissions

    file_system: *FileSystem,

    const SubData = union(enum) {
        file: File,
        dir: Dir,

        const File = struct {
            contents: std.ArrayListAlignedUnmanaged(u8, page_size_alignment),
        };

        const Dir = struct {
            entries: std.StringArrayHashMapUnmanaged(*Entry) = .{},
        };
    };

    fn createFile(
        file_system: *FileSystem,
        name: []const u8,
        contents: []const u8,
        current_time: i128,
    ) error{OutOfMemory}!*Entry {
        const dupe_name = try file_system.backend.allocator.dupe(u8, name);
        errdefer file_system.backend.allocator.free(dupe_name);

        var new_contents: std.ArrayListAlignedUnmanaged(u8, page_size_alignment) = try .initCapacity(
            file_system.backend.allocator,
            contents.len,
        );
        errdefer new_contents.deinit(file_system.backend.allocator);

        new_contents.insertSlice(file_system.backend.allocator, 0, contents) catch unreachable;

        const entry = try file_system.backend.allocator.create(Entry);
        errdefer file_system.backend.allocator.destroy(entry);

        entry.* = .{
            .file_system = file_system,
            .name = dupe_name,
            .atime = current_time,
            .mtime = current_time,
            .ctime = current_time,
            .subdata = .{ .file = .{ .contents = new_contents } },
        };

        return entry;
    }

    fn createDir(
        file_system: *FileSystem,
        name: []const u8,
        current_time: i128,
    ) error{OutOfMemory}!*Entry {
        const dupe_name = try file_system.backend.allocator.dupe(u8, name);
        errdefer file_system.backend.allocator.free(dupe_name);

        const entry = try file_system.backend.allocator.create(Entry);
        errdefer file_system.backend.allocator.destroy(entry);

        entry.* = .{
            .file_system = file_system,
            .name = dupe_name,
            .atime = current_time,
            .mtime = current_time,
            .ctime = current_time,
            .subdata = .{ .dir = .{} },
        };

        return entry;
    }

    /// Add an entry to the parent entry.
    ///
    /// The parent entry must be a directory.
    fn addEntry(
        parent: *Entry,
        entry: *Entry,
        current_time: i128,
    ) error{ DuplicateEntry, OutOfMemory }!void {
        std.debug.assert(parent.subdata == .dir);

        const get_or_put_result = try parent.subdata.dir.entries.getOrPut(
            parent.file_system.backend.allocator,
            entry.name,
        );
        if (get_or_put_result.found_existing) return error.DuplicateEntry;
        get_or_put_result.value_ptr.* = entry;

        if (entry.parent) |old_parent| {
            old_parent.ctime = current_time;
        } else {
            entry.incrementReference();
        }

        entry.ctime = current_time;

        entry.parent = parent;
        parent.ctime = current_time;
    }

    /// Remove an entry from the given entry
    ///
    /// `self` must be a directory
    ///
    /// Returns true if the entry has been destroyed
    fn removeEntry(self: *Entry, entry: *Entry, current_time: i128) bool {
        std.debug.assert(self.subdata == .dir);

        if (self.subdata.dir.entries.swapRemove(entry.name)) {
            self.ctime = current_time;

            if (entry.decrementReference()) {
                return true;
            }

            entry.ctime = current_time;
            entry.parent = null;
            return false;
        }

        return false;
    }

    inline fn incrementReference(self: *Entry) void {
        self.ref_count += 1;
    }

    /// Returns `true` if the entry has been destroyed
    fn decrementReference(self: *Entry) bool {
        self.ref_count -= 1;

        if (self.ref_count == 0) {
            _ = self.file_system.entries.remove(self);
            self.destroy();
            return true;
        }

        return false;
    }

    fn destroy(self: *Entry) void {
        self.file_system.backend.allocator.free(self.name);
        switch (self.subdata) {
            .file => |*file| file.contents.deinit(self.file_system.backend.allocator),
            .dir => |*dir| dir.entries.deinit(self.file_system.backend.allocator),
        }
        self.file_system.backend.allocator.destroy(self);
    }
};

const View = struct {
    entry: *Entry,
    position: usize = 0,

    file_system: *FileSystem,

    fn destroy(self: *View) void {
        self.file_system.backend.allocator.destroy(self);
    }
};

const Path = struct {
    path: []const u8,
    search_root: *Entry,
};

pub const FileSystemDescription = struct {
    allocator: std.mem.Allocator,

    /// This is only used to keep hold of all the created entries for them to be freed.
    entries: std.ArrayListUnmanaged(*EntryDescription),

    /// Do not assign directly.
    cwd: *EntryDescription,

    root: EntryDescription,

    pub fn create(allocator: std.mem.Allocator) !*FileSystemDescription {
        const self = try allocator.create(FileSystemDescription);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .entries = .empty,
            .root = .{
                .file_system_description = self,
                .name = "root",
                .subdata = .{ .dir = .{ .entries = .empty } },
            },
            .cwd = &self.root,
        };

        return self;
    }

    pub fn destroy(self: *FileSystemDescription) void {
        for (self.entries.items) |entry| entry.deinit();
        self.entries.deinit(self.allocator);
        self.root.subdata.dir.entries.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Set the current working directory.
    ///
    /// `entry` must be a directory.
    pub fn setCwd(self: *FileSystemDescription, entry: *EntryDescription) void {
        std.debug.assert(entry.subdata == .dir); // cwd must be a directory
        self.cwd = entry;
    }

    pub const EntryDescription = struct {
        file_system_description: *FileSystemDescription,
        name: []const u8,

        /// time of last access, if null is set to current time at construction
        atime: ?i128 = null,
        /// time of last modification, if null is set to current time at construction
        mtime: ?i128 = null,
        /// time of last status change, if null is set to current time at construction
        ctime: ?i128 = null,

        /// contains data specific to different entry types
        subdata: SubData,

        const SubData = union(enum) {
            file: File,
            dir: Dir,

            const File = struct {
                contents: []const u8,
            };

            const Dir = struct {
                entries: std.StringArrayHashMapUnmanaged(*EntryDescription) = .{},
            };
        };

        /// Add a file entry description to this directory entry description.
        ///
        /// `self` must be a directory entry description.
        ///
        /// `name` and `content` are duplicated.
        pub fn addFile(self: *EntryDescription, name: []const u8, content: []const u8) !void {
            std.debug.assert(self.subdata == .dir);
            const allocator = self.file_system_description.allocator;

            const duped_name = try allocator.dupe(u8, name);
            errdefer allocator.free(duped_name);

            const duped_content = try allocator.dupe(u8, content);
            errdefer allocator.free(duped_content);

            const file = try allocator.create(EntryDescription);
            errdefer allocator.destroy(file);

            file.* = .{
                .file_system_description = self.file_system_description,
                .name = duped_name,
                .subdata = .{ .file = .{ .contents = duped_content } },
            };

            const result = try self.subdata.dir.entries.getOrPut(allocator, duped_name);
            if (result.found_existing) return error.DuplicateEntryName;

            result.value_ptr.* = file;
            errdefer _ = self.subdata.dir.entries.pop();

            try self.file_system_description.entries.append(allocator, file);
        }

        /// Add a directory entry description to this directory entry description.
        ///
        /// `name` is duplicated.
        ///
        /// `self` must be a directory entry description.
        pub fn addDirectory(self: *EntryDescription, name: []const u8) !*EntryDescription {
            std.debug.assert(self.subdata == .dir);
            const allocator = self.file_system_description.allocator;

            const duped_name = try allocator.dupe(u8, name);
            errdefer allocator.free(duped_name);

            const dir = try allocator.create(EntryDescription);
            errdefer allocator.destroy(dir);

            dir.* = .{
                .file_system_description = self.file_system_description,
                .name = duped_name,
                .subdata = .{ .dir = .{} },
            };

            const result = try self.subdata.dir.entries.getOrPut(allocator, duped_name);
            if (result.found_existing) return error.DuplicateEntryName;

            result.value_ptr.* = dir;
            errdefer _ = self.subdata.dir.entries.pop();

            try self.file_system_description.entries.append(allocator, dir);

            return dir;
        }

        fn deinit(self: *EntryDescription) void {
            const allocator = self.file_system_description.allocator;

            switch (self.subdata) {
                .file => |file| allocator.free(file.contents),
                .dir => |*dir| dir.entries.deinit(allocator),
            }

            allocator.free(self.name);
            allocator.destroy(self);
        }
    };
};

const page_size_alignment: std.mem.Alignment = .fromByteUnits(std.heap.page_size_min);

const target_os = @import("target_os").target_os;
const TestBackend = @import("TestBackend.zig");
const System = @import("../System.zig");

const std = @import("std");
