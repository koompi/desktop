#!/usr/bin/env bash
# A dropped RRULE silently hides every recurring meeting, which looks identical to an
# empty week. Runs services/ics.js under bun against a Google-shaped .ics. No network.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ICS_JS="$REPO_ROOT/dots/.config/quickshell/koompi/services/ics.js"

[[ -f "$ICS_JS" ]] || { echo "missing $ICS_JS" >&2; exit 1; }
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$ICS_JS" "$tmp/ics.js"
# The file is QML-flavoured JS with no exports; expose its functions to the test.
printf '\nexport { parseEvents, parseDate, unfold };\n' >> "$tmp/ics.js"

cat > "$tmp/run.mjs" <<'EOF'
import { parseEvents, parseDate, unfold } from "./ics.js";

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};

// Folded SUMMARY, an all-day event, a weekly standup with an EXDATE hole,
// a daily event capped by COUNT, and one already in the past.
const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "BEGIN:VEVENT",
    "DTSTART:20260803T090000Z",
    "DTEND:20260803T093000Z",
    "SUMMARY:Standup with a very long title that Google will",
    "  fold onto a second line",
    // UNTIL lands inside the query window on purpose: a parser that ignores it
    // would otherwise still look correct, because the window would cap it.
    "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20260817T000000Z",
    "EXDATE:20260805T090000Z",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "DTSTART;VALUE=DATE:20260805",
    "DTEND;VALUE=DATE:20260806",
    "SUMMARY:Public holiday",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "DTSTART:20260804T140000Z",
    "DTEND:20260804T150000Z",
    "SUMMARY:Daily sync\\, three times only",
    "RRULE:FREQ=DAILY;COUNT=3",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "DTSTART:20200101T100000Z",
    "DTEND:20200101T110000Z",
    "SUMMARY:Long gone",
    "END:VEVENT",
    "END:VCALENDAR",
].join("\r\n");

const from = new Date(Date.UTC(2026, 7, 1));
const to = new Date(Date.UTC(2026, 7, 31));
const events = parseEvents(ics, from, to);

check("line unfolding", unfold("A:1\r\n  2").includes("1 2") || unfold("A:1\r\n 2") === "A:1 2");

const standups = events.filter(e => e.summary.startsWith("Standup"));
check("recurring event expands", standups.length > 1, `got ${standups.length}`);
check("folded SUMMARY rejoined", standups[0]?.summary.includes("fold onto a second line"),
      JSON.stringify(standups[0]?.summary));
const standupDays = new Set(standups.map(e => e.start.getDay()));
check("BYDAY honoured: only Mon and Wed",
      standups.every(e => [1, 3].includes(e.start.getDay())),
      [...standupDays].join(","));
check("BYDAY honoured: both Mon and Wed present",
      standupDays.has(1) && standupDays.has(3),
      [...standupDays].join(","));
check("EXDATE removes its instance",
      !standups.some(e => e.start.toISOString().startsWith("2026-08-05")),
      standups.map(e => e.start.toISOString()).join(" "));
check("UNTIL caps the series before the window ends",
      standups.every(e => e.start < new Date(Date.UTC(2026, 7, 17))),
      standups.map(e => e.start.toISOString()).join(" "));

const daily = events.filter(e => e.summary.startsWith("Daily sync"));
check("COUNT caps the series", daily.length === 3, `got ${daily.length}`);
check("escaped comma unescaped", daily[0]?.summary.includes("sync, three"), daily[0]?.summary);

const holiday = events.find(e => e.summary === "Public holiday");
check("all-day event parsed", !!holiday);
check("all-day flagged", holiday?.allDay === true);

check("out-of-window event dropped", !events.some(e => e.summary === "Long gone"));
check("sorted by start", events.every((e, i) => i === 0 || events[i - 1].start <= e.start));
check("date-only parse", parseDate("20260731")?.getFullYear() === 2026);
check("garbage date rejected", parseDate("not-a-date") === null);

if (failed) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log(`ics parse test passed (${events.length} instances)`);
EOF

cd "$tmp" && bun run run.mjs
