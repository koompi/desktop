// J19 runnable checks for the pure-JS findings. Exit 1 on any failure.
const fs = require("fs");
const vm = require("vm");
const ROOT = "/home/userx/.herdr/worktrees/koompi-desktop/j19-shell-modules-bugs/dots/.config/quickshell/koompi";
let failed = 0;
function check(name, got, want) {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    console.log(`${ok ? "ok  " : "FAIL"} ${name}: got ${JSON.stringify(got)}${ok ? "" : " want " + JSON.stringify(want)}`);
    if (!ok) failed++;
}

// L1: month-length helpers, straight from the file
const cal = {};
vm.runInNewContext(fs.readFileSync(`${ROOT}/modules/koompi/sidebarRight/calendar/calendar_layout.js`, "utf8")
    + "\nthis.getNextMonthDays = getNextMonthDays; this.getPrevMonthDays = getPrevMonthDays; this.getMonthDays = getMonthDays;", cal);
check("L1 getNextMonthDays(7, 2026) (August)", cal.getNextMonthDays(7, 2026), 31);
check("L1 getPrevMonthDays(8, 2026) (July)", cal.getPrevMonthDays(8, 2026), 31);
check("L1 getNextMonthDays(12, 2027) (Jan 2028)", cal.getNextMonthDays(12, 2027), 31);
check("L1 getPrevMonthDays(1, 2028) (Dec 2027)", cal.getPrevMonthDays(1, 2028), 31);
check("L1 getNextMonthDays(1, 2028) (leap Feb)", cal.getNextMonthDays(1, 2028), 29);
check("L1 getPrevMonthDays(3, 2027) (Feb)", cal.getPrevMonthDays(3, 2027), 28);
let l1all = true;
for (let m = 1; m <= 12; m++) {
    const next = m === 12 ? new Date(2027, 0, 0) : new Date(2026, m + 1, 0); // last day of month m+1
    const prev = new Date(2026, m - 1, 0);
    if (cal.getNextMonthDays(m, 2026) !== next.getDate() || cal.getPrevMonthDays(m, 2026) !== prev.getDate()) l1all = false;
}
check("L1 all twelve months of 2026 agree with Date", l1all, true);

// M9: DateUtils.getIthDayDateOfSameWeek with firstDay undefined (the typo) vs 0 (Sunday-first locale)
function getFirstDayOfWeek(date, firstDay = 1) { const d = new Date(date); const diff = (d.getDay() - firstDay + 7) % 7; d.setDate(d.getDate() - diff); return d; }
function getIthDayDateOfSameWeek(date, i, firstDay = 1) { const f = getFirstDayOfWeek(date, firstDay); const t = new Date(f); t.setDate(f.getDate() + i); return t; }
const wed = new Date(2026, 0, 7); // Wednesday 7 Jan 2026; Sunday-first week is 4..10 Jan
const typo = getIthDayDateOfSameWeek(wed, 6 - 0, undefined).getDate();
const fixed = getIthDayDateOfSameWeek(wed, 6 - 0, 0).getDate();
check("M9 firstdayOfWeek (undefined) lands on", typo, 11);
check("M9 firstDayOfWeek = 0 lands on Saturday", fixed, 10);
const src = fs.readFileSync(`${ROOT}/modules/common/widgets/CalendarView.qml`, "utf8");
check("M9 CalendarView no longer reads firstdayOfWeek", src.includes("firstdayOfWeek"), false);

// M10: the duplicate predicate, before and after
const before = (p1, p2) => p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2);
const after = (p1, p2) => (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle))) || (Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2);
const a = { trackTitle: "Song A", position: 10, length: 200 };
const b = { trackTitle: "Song B", position: 120, length: 300 };
check("M10 before: A behind B counts as duplicate", !!before(a, b), true);
check("M10 after: A behind B is not a duplicate", !!after(a, b), false);
check("M10 after: B ahead of A is not a duplicate", !!after(b, a), false);
check("M10 after: same title still groups", !!after(a, { trackTitle: "Song A (Remastered)", position: 0, length: 0 }), true);
check("M10 after: same position and length still groups", !!after(a, { trackTitle: "", position: 11, length: 199 }), true);
const mc = fs.readFileSync(`${ROOT}/modules/koompi/mediaControls/MediaControls.qml`, "utf8");
check("M10 MediaControls carries the abs form", mc.includes("Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2"), true);

// M12: the binding body, with the service's initial data
const data = { temp: 0 };
let threw = false;
try { void (data?.temp.substring(0, data?.temp.length - 1) ?? "--°"); } catch (e) { threw = e.constructor.name; }
check("M12 old expression on temp: 0 throws", threw, "TypeError");
const widget = d => typeof d?.temp === "string" ? d.temp.substring(0, d.temp.length - 1) : "--°";
check("M12 new expression on temp: 0", widget(data), "--°");
check("M12 new expression on temp: '25°C'", widget({ temp: "25°C" }), "25°");
check("M12 new expression on undefined data", widget(undefined), "--°");

// L9: array-vs-literal comparison
check("L9 [] == [] is", [] == [], false);
check("L9 [].length === 0 is", [].length === 0, true);

// M19: identify output parsing, as in Background.qml
const parse = text => { const output = text.trim(); const [w, h] = output.split(" ").map(Number); return (Number.isFinite(w) && w > 0 && Number.isFinite(h) && h > 0) ? [w, h] : null; };
const oldParse = text => { const [w, h] = text.split(" ").map(Number); return Math.max(1920 / w, 1200 / h); };
check("M19 old parse of empty output gives", String(oldParse("")), "NaN");
check("M19 new parse of empty output", parse(""), null);
check("M19 new parse of 'identify: unable to open image'", parse("identify: unable to open image"), null);
check("M19 new parse of '3840 2160'", parse("3840 2160\n"), [3840, 2160]);
check("M19 new parse of animated output '640 480640 480'", parse("640 480640 480"), [640, 480640]);
process.exit(failed ? 1 : 0);
