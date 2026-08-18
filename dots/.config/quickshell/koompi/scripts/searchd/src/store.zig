const std = @import("std");
const match = @import("match.zig");

/// A wholesale-replaced in-memory dataset for `clipboard` and `apps`, pushed
/// by QML rather than walked or watched by the daemon itself: `clipboard`
/// changes on a Wayland clipboard signal only QML sees, and `apps` changes on
/// `DesktopEntries`, both already tracked client-side (`Cliphist.entries`,
/// `AppSearch.list`) with no daemon-visible equivalent to watch. See
/// PROTOCOL.md's `update` command.
///
/// Scoring is the same bounded smart-case substring match as `files`'
/// `Index.query`, not a fuzzysort port - PROTOCOL.md documents this as an
/// explicit, evidence-driven scope decision (Phase 1's benchmark already
/// showed both domains' JS-side fuzzysort scan is sub-millisecond even at
/// 10x stress scale, so the question this store exists to answer is whether
/// a daemon round trip can still clear the >=25% P95 gate against that,
/// not whether it can out-rank fuzzysort - it does not attempt to).
///
/// Privacy: `entries` for `service == "clipboard"` is clipboard content held
/// in RAM for exactly the reason `Cliphist.entries` already holds it there -
/// to search it. Nothing here writes it to a log, a file, or a panic path;
/// grep-checked in tests/test_searchd.py.
pub const Store = struct {
    gpa: std.mem.Allocator,
    entries: std.ArrayList(Entry),

    pub const Entry = struct {
        /// What a client re-identifies the match by. Clipboard: the raw
        /// `<id>\t<preview>` line, matching `Cliphist.entries`'s own shape.
        /// Apps: the `.desktop` id.
        id: []u8,
        /// What is actually matched against `query`.
        name: []u8,
    };

    pub fn init(gpa: std.mem.Allocator) Store {
        return .{ .gpa = gpa, .entries = .empty };
    }

    pub fn deinit(self: *Store) void {
        self.clear();
        self.entries.deinit(self.gpa);
    }

    fn clear(self: *Store) void {
        for (self.entries.items) |e| {
            self.gpa.free(e.id);
            self.gpa.free(e.name);
        }
        self.entries.clearRetainingCapacity();
    }

    /// Replaces the whole dataset. `raw` pairs are (id, name) as read
    /// straight from the request's JSON; copied, never retained by
    /// reference into the request's own transient arena.
    pub fn replace(self: *Store, raw: []const [2][]const u8) !void {
        self.clear();
        try self.entries.ensureTotalCapacity(self.gpa, raw.len);
        for (raw) |pair| {
            self.entries.appendAssumeCapacity(.{
                .id = try self.gpa.dupe(u8, pair[0]),
                .name = try self.gpa.dupe(u8, pair[1]),
            });
        }
    }

    pub const Match = struct { id: []const u8, name: []const u8 };

    pub fn query(self: *const Store, q: []const u8, limit: usize, out: []Match) usize {
        const case_sensitive = match.isCaseSensitive(q);
        var found: usize = 0;
        for (self.entries.items) |e| {
            if (!match.contains(e.name, q, case_sensitive)) continue;
            if (found < out.len) out[found] = .{ .id = e.id, .name = e.name };
            found += 1;
        }
        return @min(found, limit);
    }

    pub fn countMatches(self: *const Store, q: []const u8) usize {
        const case_sensitive = match.isCaseSensitive(q);
        var total: usize = 0;
        for (self.entries.items) |e| {
            if (match.contains(e.name, q, case_sensitive)) total += 1;
        }
        return total;
    }
};

test "replace swaps the dataset wholesale, freeing what it replaces" {
    var s = Store.init(std.testing.allocator);
    defer s.deinit();

    try s.replace(&.{ .{ "1\tfoo", "foo" }, .{ "2\tbar", "bar" } });
    try std.testing.expectEqual(@as(usize, 2), s.entries.items.len);

    try s.replace(&.{.{ "3\tbaz", "baz" }});
    try std.testing.expectEqual(@as(usize, 1), s.entries.items.len);
    try std.testing.expectEqualStrings("baz", s.entries.items[0].name);
}

test "query is smart-case substring against name, id is returned untouched" {
    var s = Store.init(std.testing.allocator);
    defer s.deinit();
    try s.replace(&.{
        .{ "app-1.desktop", "Text Editor" },
        .{ "app-2.desktop", "Terminal" },
        .{ "app-3.desktop", "text viewer" },
    });

    var out: [10]Store.Match = undefined;
    try std.testing.expectEqual(@as(usize, 2), s.query("text", 10, &out)); // case-insensitive
    try std.testing.expectEqual(@as(usize, 1), s.query("Text", 10, &out)); // case-sensitive: only "Text Editor"
    try std.testing.expectEqualStrings("app-1.desktop", out[0].id);
    try std.testing.expectEqual(@as(usize, 0), s.query("zzznomatch", 10, &out));
    try std.testing.expectEqual(@as(usize, 2), s.countMatches("text"));
}
