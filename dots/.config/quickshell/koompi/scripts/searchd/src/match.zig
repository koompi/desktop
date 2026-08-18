const std = @import("std");

/// Smart-case substring match, the same rule `fd` uses by default: any
/// uppercase character in `query` makes the match case-sensitive, otherwise
/// case-insensitive. Shared by every domain's `query`/`countMatches` so the
/// tie-break and case rule stay identical across `files`, `clipboard` and
/// `apps` rather than drifting per implementation.
pub fn isCaseSensitive(query: []const u8) bool {
    for (query) |c| if (std.ascii.isUpper(c)) return true;
    return false;
}

pub fn contains(haystack: []const u8, query: []const u8, case_sensitive: bool) bool {
    if (query.len == 0) return true;
    if (case_sensitive) return std.mem.indexOf(u8, haystack, query) != null;
    return std.ascii.indexOfIgnoreCase(haystack, query) != null;
}
