const std = @import("std");
const linux = std.os.linux;

/// A persistent, `inotify`-maintained index of regular files under one root
/// directory, scoped the way `fd`'s own default posture scopes it:
/// - every path component starting with `.` is skipped (matching `fd`'s
///   default, non-`--hidden` behavior - FileSearch.qml passes `--hidden`
///   instead; see PROTOCOL.md for why the index deliberately does not match
///   that one flag - on a real dev machine, dotdirs were >95% of the file
///   count and none of the cost, which is the whole reason a persistent index
///   is worth building here);
/// - `node_modules`, and anything a `.gitignore` in an ancestor directory
///   covers, the same as `fd`'s own default `.gitignore`-respecting behavior.
///   Measured on a real `$HOME` with ~20 project checkouts: without
///   `.gitignore` awareness the index held 222,141 files; with it, 143,497 -
///   still short of `fd`'s own 74,164 because the subset below is bounded,
///   not a full implementation, but the gap was almost entirely per-project
///   build output and dependency content scattered across every checkout, not
///   concentrated in a few well-known directory names, so a short hardcoded
///   exclude list could not have closed most of it on its own.
///
/// The `.gitignore` support is a bounded subset: only patterns with no `/`
/// (the common case: `*.pyc`, `dist`, `__pycache__`) are honored, matched
/// against the basename at any depth below the `.gitignore` that declared
/// them, with a single `*` wildcard. Negation (`!pattern`) and slash-anchored
/// patterns are parsed but skipped rather than applied, which only ever
/// under-excludes (a file that should have been unignored by a `!` rule just
/// stays out of the index), never over-excludes.
///
/// Patterns are stored once, at the directory whose own `.gitignore` declared
/// them (`WatchedDir.own_patterns`, empty for the overwhelming majority of
/// directories) rather than copied into every descendant - an early version
/// accumulated the full ancestor chain into every directory's own storage,
/// which measured ~54MB steady PSS against a 10MB budget on this same
/// `$HOME`. `collectPatterns` walks the cheap `parent_wd` chain instead.
///
/// No polling: every directory the walk visits gets one inotify watch, and
/// CREATE/DELETE/MOVED_FROM/MOVED_TO/DELETE_SELF keep the index and the watch
/// set in sync afterward. IN_Q_OVERFLOW (the queue dropped events) triggers a
/// full rebuild rather than trying to reconcile from a gap.
pub const Index = struct {
    gpa: std.mem.Allocator,
    root: []u8,
    entries: std.ArrayList([]u8),
    watch_dirs: std.AutoHashMap(i32, WatchedDir),
    inotify_fd: i32,
    build_ms: f64 = 0,

    const WatchedDir = struct {
        path: []u8,
        parent_wd: i32, // -1 for the root, which has no parent
        /// This directory's own `.gitignore` patterns only, not inherited -
        /// empty for every directory without one of its own.
        own_patterns: [][]u8,
    };

    const excluded_names = [_][]const u8{"node_modules"};
    const dirent64_name_offset = @offsetOf(linux.dirent64, "type") + 1;
    const watch_mask: u32 = linux.IN.CREATE | linux.IN.DELETE | linux.IN.MOVED_FROM |
        linux.IN.MOVED_TO | linux.IN.DELETE_SELF | linux.IN.ONLYDIR;
    const max_gitignore_bytes = 256 * 1024;
    const no_parent: i32 = -1;

    pub fn init(gpa: std.mem.Allocator, root: []const u8) !Index {
        const rc = std.c.inotify_init1(@as(c_uint, linux.IN.CLOEXEC));
        if (rc < 0) return error.InotifyInitFailed;

        var self: Index = .{
            .gpa = gpa,
            .root = try gpa.dupe(u8, root),
            .entries = .empty,
            .watch_dirs = std.AutoHashMap(i32, WatchedDir).init(gpa),
            .inotify_fd = rc,
        };
        try self.rebuild();
        return self;
    }

    pub fn deinit(self: *Index) void {
        for (self.entries.items) |p| self.gpa.free(p);
        self.entries.deinit(self.gpa);
        self.freeWatchedDirs();
        self.watch_dirs.deinit();
        self.gpa.free(self.root);
        _ = linux.close(self.inotify_fd);
    }

    fn freeWatchedDirs(self: *Index) void {
        var it = self.watch_dirs.valueIterator();
        while (it.next()) |wdir| self.freeWatchedDir(wdir.*);
    }

    fn freeWatchedDir(self: *Index, wdir: WatchedDir) void {
        self.gpa.free(wdir.path);
        for (wdir.own_patterns) |p| self.gpa.free(p);
        self.gpa.free(wdir.own_patterns);
    }

    /// Drops every watch and every entry, then walks `root` from scratch. Used
    /// at startup and to recover from IN_Q_OVERFLOW.
    pub fn rebuild(self: *Index) !void {
        const started = monotonicNs();

        for (self.entries.items) |p| self.gpa.free(p);
        self.entries.clearRetainingCapacity();
        self.freeWatchedDirs();
        self.watch_dirs.clearRetainingCapacity();

        try self.walk(self.root, no_parent);
        self.build_ms = @as(f64, @floatFromInt(monotonicNs() - started)) / 1e6;
    }

    fn monotonicNs() i128 {
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
    }

    /// Strips the `root/` prefix `entries` are stored without - every path
    /// under `root` starts with it by construction, so this only degrades to
    /// returning `abs` unchanged if that invariant is ever violated.
    /// `entries` storing paths this way instead of absolute cut steady PSS
    /// against a real `$HOME` (143K entries, deeply nested workspace paths)
    /// from ~25MB to within budget, since the same root prefix was otherwise
    /// duplicated in every single one of them.
    fn relPath(self: *const Index, abs: []const u8) []const u8 {
        if (std.mem.startsWith(u8, abs, self.root) and abs.len > self.root.len and abs[self.root.len] == '/') {
            return abs[self.root.len + 1 ..];
        }
        return abs;
    }

    fn skipName(name: []const u8) bool {
        if (name.len == 0) return true;
        if (name[0] == '.') return true;
        for (excluded_names) |ex| if (std.mem.eql(u8, name, ex)) return true;
        return false;
    }

    fn matchesAny(patterns: []const []const u8, name: []const u8) bool {
        for (patterns) |pat| if (globMatch(pat, name)) return true;
        return false;
    }

    /// `*` matches any run of characters (patterns here never contain `/`);
    /// everything else is literal. Classic two-pointer wildcard match.
    fn globMatch(pattern: []const u8, name: []const u8) bool {
        var pi: usize = 0;
        var ni: usize = 0;
        var star_pi: ?usize = null;
        var star_ni: usize = 0;
        while (ni < name.len) {
            if (pi < pattern.len and pattern[pi] == name[ni]) {
                pi += 1;
                ni += 1;
            } else if (pi < pattern.len and pattern[pi] == '*') {
                star_pi = pi;
                star_ni = ni;
                pi += 1;
            } else if (star_pi) |sp| {
                pi = sp + 1;
                star_ni += 1;
                ni = star_ni;
            } else return false;
        }
        while (pi < pattern.len and pattern[pi] == '*') pi += 1;
        return pi == pattern.len;
    }

    /// Walks the `parent_wd` chain starting at (and including) `wd`,
    /// collecting every ancestor's `own_patterns` into `out` by reference -
    /// `out`'s entries borrow storage owned by `watch_dirs`, never copied.
    fn collectPatterns(self: *Index, wd: i32, out: *std.ArrayList([]const u8)) !void {
        var current = wd;
        while (current != no_parent) {
            const w = self.watch_dirs.get(current) orelse return;
            for (w.own_patterns) |p| try out.append(self.gpa, p);
            current = w.parent_wd;
        }
    }

    /// Reads `dir_path/.gitignore` if present and returns its usable patterns
    /// (owned copies), skipping blank lines, `#` comments, negation (`!`) and
    /// any pattern containing `/` (anchored patterns - out of scope for this
    /// bounded subset, see the doc comment on `Index`). Absent file, read
    /// error or oversize file all just yield zero patterns rather than
    /// failing the walk.
    fn readGitignore(self: *Index, dir_path: []const u8) ![][]u8 {
        const path = try std.fs.path.joinZ(self.gpa, &.{ dir_path, ".gitignore" });
        defer self.gpa.free(path);

        const fd_rc = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
        const fd: i32 = switch (linux.errno(fd_rc)) {
            .SUCCESS => @intCast(fd_rc),
            else => return &[_][]u8{},
        };
        defer _ = linux.close(fd);

        const buf = try self.gpa.alloc(u8, max_gitignore_bytes);
        defer self.gpa.free(buf);
        var len: usize = 0;
        while (len < buf.len) {
            const n = linux.read(fd, buf.ptr + len, buf.len - len);
            if (linux.errno(n) != .SUCCESS or n == 0) break;
            len += n;
        }

        var patterns: std.ArrayList([]u8) = .empty;
        errdefer {
            for (patterns.items) |p| self.gpa.free(p);
            patterns.deinit(self.gpa);
        }

        var lines = std.mem.splitScalar(u8, buf[0..len], '\n');
        while (lines.next()) |raw| {
            var line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;
            if (line.len > 1 and line[line.len - 1] == '/') line = line[0 .. line.len - 1];
            if (line.len == 0 or std.mem.indexOfScalar(u8, line, '/') != null) continue;
            try patterns.append(self.gpa, try self.gpa.dupe(u8, line));
        }
        return patterns.toOwnedSlice(self.gpa);
    }

    fn walk(self: *Index, dir_path: []const u8, parent_wd: i32) !void {
        const dir_path_z = try self.gpa.dupeZ(u8, dir_path);
        defer self.gpa.free(dir_path_z);

        const fd_rc = linux.open(dir_path_z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        const fd: i32 = switch (linux.errno(fd_rc)) {
            .SUCCESS => @intCast(fd_rc),
            else => return, // vanished, permission denied, or not a real directory - skip it, not fatal
        };
        defer _ = linux.close(fd);

        const own_patterns = try self.readGitignore(dir_path);
        const wd = std.c.inotify_add_watch(self.inotify_fd, dir_path_z, watch_mask);
        if (wd < 0) {
            for (own_patterns) |p| self.gpa.free(p);
            self.gpa.free(own_patterns);
            return;
        }
        try self.watch_dirs.put(wd, .{ .path = try self.gpa.dupe(u8, dir_path), .parent_wd = parent_wd, .own_patterns = own_patterns });

        var effective: std.ArrayList([]const u8) = .empty;
        defer effective.deinit(self.gpa);
        try self.collectPatterns(wd, &effective);

        var buf: [8192]u8 align(8) = undefined;
        while (true) {
            const n = linux.getdents64(fd, &buf, buf.len);
            if (linux.errno(n) != .SUCCESS) break;
            if (n == 0) break;

            var off: usize = 0;
            while (off < n) {
                const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
                // d_name starts right after d_type with no padding (the kernel's
                // flexible-array-member ABI) - @sizeOf(dirent64) is 24, rounded up
                // for the struct's 8-byte alignment, and using it here reads 5
                // bytes into the name instead of its start.
                const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&buf[off + dirent64_name_offset])), 0);
                off += d.reclen;

                if (skipName(name) or matchesAny(effective.items, name)) continue;

                const child = try std.fs.path.join(self.gpa, &.{ dir_path, name });
                defer self.gpa.free(child);

                if (d.type == linux.DT.DIR) {
                    try self.walk(child, wd);
                } else if (d.type == linux.DT.REG) {
                    try self.entries.append(self.gpa, try self.gpa.dupe(u8, self.relPath(child)));
                }
                // DT_UNKNOWN (rare, some overlay/network filesystems) and
                // symlinks are neither indexed nor recursed into - `fd`
                // dereferences symlinks by default too, which this does not
                // attempt to match; a symlinked file just does not appear.
            }
        }
    }

    /// Applies every event currently queued on `inotify_fd`. Call after `poll`
    /// reports it readable. Returns true if a rebuild was needed (queue
    /// overflow), so the caller can log it.
    pub fn drainEvents(self: *Index) !bool {
        var buf: [8192]u8 align(@alignOf(linux.inotify_event)) = undefined;
        const n_isize = std.c.read(self.inotify_fd, &buf, buf.len);
        if (n_isize <= 0) return false;
        const n: usize = @intCast(n_isize);

        var off: usize = 0;
        var overflowed = false;
        while (off < n) {
            const ev: *align(1) const linux.inotify_event = @ptrCast(&buf[off]);
            off += @sizeOf(linux.inotify_event) + ev.len;

            if (ev.mask & linux.IN.Q_OVERFLOW != 0) {
                overflowed = true;
                continue;
            }
            self.applyEvent(ev) catch continue;
        }

        if (overflowed) {
            try self.rebuild();
            return true;
        }
        return false;
    }

    fn applyEvent(self: *Index, ev: *align(1) const linux.inotify_event) !void {
        const wdir = self.watch_dirs.get(ev.wd) orelse return;
        const is_dir = ev.mask & linux.IN.ISDIR != 0;

        if (ev.mask & linux.IN.DELETE_SELF != 0) {
            self.removeSubtree(wdir.path);
            return;
        }

        if (ev.len == 0) return;
        const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(@as([*]const u8, @ptrCast(ev)) + @sizeOf(linux.inotify_event))), 0);
        if (skipName(name)) return;

        var effective: std.ArrayList([]const u8) = .empty;
        defer effective.deinit(self.gpa);
        try self.collectPatterns(ev.wd, &effective);
        if (matchesAny(effective.items, name)) return;

        const child = try std.fs.path.join(self.gpa, &.{ wdir.path, name });
        defer self.gpa.free(child);

        if (ev.mask & (linux.IN.CREATE | linux.IN.MOVED_TO) != 0) {
            if (is_dir) {
                try self.walk(child, ev.wd);
            } else {
                const rel = self.relPath(child);
                for (self.entries.items) |p| if (std.mem.eql(u8, p, rel)) return;
                try self.entries.append(self.gpa, try self.gpa.dupe(u8, rel));
            }
            return;
        }
        if (ev.mask & (linux.IN.DELETE | linux.IN.MOVED_FROM) != 0) {
            if (is_dir) {
                self.removeSubtree(child);
            } else {
                self.removeEntry(self.relPath(child));
            }
        }
    }

    fn removeEntry(self: *Index, path: []const u8) void {
        for (self.entries.items, 0..) |p, i| {
            if (std.mem.eql(u8, p, path)) {
                self.gpa.free(p);
                _ = self.entries.swapRemove(i);
                return;
            }
        }
    }

    fn underOrEqual(p: []const u8, dir_path: []const u8) bool {
        return std.mem.eql(u8, p, dir_path) or
            (std.mem.startsWith(u8, p, dir_path) and p.len > dir_path.len and p[dir_path.len] == '/');
    }

    /// Drops every entry and watch under `dir_path`, inclusive.
    fn removeSubtree(self: *Index, dir_path: []const u8) void {
        const rel_dir = self.relPath(dir_path);
        var i: usize = 0;
        while (i < self.entries.items.len) {
            const p = self.entries.items[i];
            if (underOrEqual(p, rel_dir)) {
                self.gpa.free(p);
                _ = self.entries.swapRemove(i);
                continue;
            }
            i += 1;
        }

        var stale = std.ArrayList(i32).empty;
        defer stale.deinit(self.gpa);
        var it = self.watch_dirs.iterator();
        while (it.next()) |entry| {
            if (underOrEqual(entry.value_ptr.path, dir_path)) {
                stale.append(self.gpa, entry.key_ptr.*) catch continue;
            }
        }
        for (stale.items) |wd| {
            if (self.watch_dirs.fetchRemove(wd)) |kv| self.freeWatchedDir(kv.value);
            _ = std.c.inotify_rm_watch(self.inotify_fd, wd);
        }
    }

    pub const Match = struct { path: []const u8, name: []const u8 };

    /// Substring match, smart-case like `fd`: any uppercase in `query` makes it
    /// case-sensitive, otherwise case-insensitive. A `query` containing `/`
    /// matches the full (root-relative) path, matching FileSearch.qml:80's
    /// `--full-path` branch; otherwise only the basename. Results are
    /// returned in index order (the walk's own directory order) - see
    /// PROTOCOL.md's tie-break.
    ///
    /// `out[].path` is allocated with `allocator` (the real absolute path,
    /// `root` rejoined onto the relative form `entries` stores) - only for
    /// the capped, returned set, never for the full scan.
    ///
    /// `total` is the full match count, independent of `limit` - counted in
    /// the same pass rather than a second scan (an earlier version called a
    /// separate `countMatches`, doubling every real query's cost; measured
    /// against this box's ~143K-entry `$HOME`, that alone was most of a
    /// ~20-25ms round trip).
    pub const Result = struct { returned: usize, total: usize };

    pub fn query(self: *const Index, allocator: std.mem.Allocator, q: []const u8, limit: usize, out: []Match) !Result {
        const full_path = std.mem.indexOfScalar(u8, q, '/') != null;
        var case_sensitive = false;
        for (q) |c| if (std.ascii.isUpper(c)) {
            case_sensitive = true;
            break;
        };

        var found: usize = 0;
        for (self.entries.items) |p| {
            const name = std.fs.path.basename(p);
            const haystack = if (full_path) p else name;
            const hit = if (q.len == 0)
                true
            else if (case_sensitive)
                std.mem.indexOf(u8, haystack, q) != null
            else
                std.ascii.indexOfIgnoreCase(haystack, q) != null;
            if (!hit) continue;

            if (found < out.len and found < limit) out[found] = .{ .path = try std.fs.path.join(allocator, &.{ self.root, p }), .name = name };
            found += 1;
        }
        return .{ .returned = @min(found, @min(limit, out.len)), .total = found };
    }
};

test "walk indexes non-hidden regular files, skips dotdirs and node_modules, recurses subdirectories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "Documents/sub");
    try tmp.dir.createDirPath(std.testing.io, ".cache");
    try tmp.dir.createDirPath(std.testing.io, "node_modules/pkg");
    (try tmp.dir.createFile(std.testing.io, "Documents/report.pdf", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, "Documents/sub/notes.txt", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, ".cache/junk", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, "node_modules/pkg/index.js", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, ".hidden-file", .{})).close(std.testing.io);

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var idx = try Index.init(std.testing.allocator, root);
    defer idx.deinit();

    try std.testing.expectEqual(@as(usize, 2), idx.entries.items.len);
    var found_report = false;
    var found_notes = false;
    for (idx.entries.items) |p| {
        if (std.mem.endsWith(u8, p, "report.pdf")) found_report = true;
        if (std.mem.endsWith(u8, p, "notes.txt")) found_notes = true;
        try std.testing.expect(std.mem.indexOf(u8, p, "/.cache/") == null);
        try std.testing.expect(std.mem.indexOf(u8, p, "node_modules") == null);
    }
    try std.testing.expect(found_report and found_notes);
}

test "a .gitignore excludes matching basenames in its own directory and below, without a hardcoded name list" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "proj/build-output/nested");
    {
        var f = try tmp.dir.createFile(std.testing.io, "proj/.gitignore", .{});
        try f.writeStreamingAll(std.testing.io, "build-output\n*.log\n# comment\n\n!kept-anyway.log\n");
        f.close(std.testing.io);
    }
    (try tmp.dir.createFile(std.testing.io, "proj/keep.txt", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, "proj/debug.log", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, "proj/build-output/nested/artifact.bin", .{})).close(std.testing.io);

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var idx = try Index.init(std.testing.allocator, root);
    defer idx.deinit();

    try std.testing.expectEqual(@as(usize, 1), idx.entries.items.len);
    try std.testing.expect(std.mem.endsWith(u8, idx.entries.items[0], "keep.txt"));
}

test "a nested .gitignore's patterns do not leak to sibling directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "a");
    try tmp.dir.createDirPath(std.testing.io, "b");
    {
        var f = try tmp.dir.createFile(std.testing.io, "a/.gitignore", .{});
        try f.writeStreamingAll(std.testing.io, "secret.txt\n");
        f.close(std.testing.io);
    }
    (try tmp.dir.createFile(std.testing.io, "a/secret.txt", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, "b/secret.txt", .{})).close(std.testing.io);

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var idx = try Index.init(std.testing.allocator, root);
    defer idx.deinit();

    try std.testing.expectEqual(@as(usize, 1), idx.entries.items.len);
    try std.testing.expect(std.mem.startsWith(u8, std.fs.path.basename(std.fs.path.dirname(idx.entries.items[0]).?), "b"));
}

test "inotify create and delete keep the index and total live" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "Documents");

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var idx = try Index.init(std.testing.allocator, root);
    defer idx.deinit();
    try std.testing.expectEqual(@as(usize, 0), idx.entries.items.len);

    (try tmp.dir.createFile(std.testing.io, "Documents/new-report.pdf", .{})).close(std.testing.io);

    var pfd = [_]std.posix.pollfd{.{ .fd = idx.inotify_fd, .events = std.posix.POLL.IN, .revents = 0 }};
    _ = try std.posix.poll(&pfd, 2000);
    _ = try idx.drainEvents();

    try std.testing.expectEqual(@as(usize, 1), idx.entries.items.len);
    try std.testing.expect(std.mem.endsWith(u8, idx.entries.items[0], "new-report.pdf"));

    try tmp.dir.deleteFile(std.testing.io, "Documents/new-report.pdf");
    _ = try std.posix.poll(&pfd, 2000);
    _ = try idx.drainEvents();
    try std.testing.expectEqual(@as(usize, 0), idx.entries.items.len);
}

test "query is substring, smart-case, basename by default and full path with a slash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "Documents/Projects");
    (try tmp.dir.createFile(std.testing.io, "Documents/Quarterly-Report.pdf", .{})).close(std.testing.io);
    (try tmp.dir.createFile(std.testing.io, "Documents/Projects/report.txt", .{})).close(std.testing.io);

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var idx = try Index.init(std.testing.allocator, root);
    defer idx.deinit();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var out: [10]Index.Match = undefined;
    var r = try idx.query(arena, "report", 10, &out);
    try std.testing.expectEqual(@as(usize, 2), r.returned);
    try std.testing.expectEqual(@as(usize, 2), r.total);
    try std.testing.expect(std.mem.startsWith(u8, out[0].path, root));

    r = try idx.query(arena, "Report", 10, &out); // case-sensitive: only Quarterly-Report.pdf
    try std.testing.expectEqual(@as(usize, 1), r.returned);
    r = try idx.query(arena, "Documents/Projects", 10, &out); // full-path match
    try std.testing.expectEqual(@as(usize, 1), r.returned);
    r = try idx.query(arena, "zzznomatch", 10, &out);
    try std.testing.expectEqual(@as(usize, 0), r.returned);

    r = try idx.query(arena, "report", 1, &out);
    try std.testing.expectEqual(@as(usize, 1), r.returned);
    try std.testing.expectEqual(@as(usize, 2), r.total);
}
