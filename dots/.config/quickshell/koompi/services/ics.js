// Minimal iCalendar reader for Google Calendar's private .ics export: timed and
// all-day events, repeats via FREQ/INTERVAL/COUNT/UNTIL/BYDAY with EXDATE holes.
// ponytail: no VTIMEZONE, no BYMONTHDAY/BYSETPOS, no per-instance RECURRENCE-ID
// overrides. A TZID event is read as local time, which is right while your
// calendar and your laptop agree on a zone. Reach for a real ical library if
// shared or cross-zone calendars land here.

var DAY = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
var MAX_INSTANCES = 400; // guard: a malformed UNTIL must not spin forever

function unfold(text) {
    return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/\n[ \t]/g, "");
}

function unescapeText(s) {
    return s.replace(/\\n/gi, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\");
}

// 20260731T090000Z | 20260731T090000 | 20260731
function parseDate(v) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(String(v).trim());
    if (!m)
        return null;
    var y = +m[1], mo = +m[2] - 1, d = +m[3];
    var hh = m[4] ? +m[4] : 0, mi = m[5] ? +m[5] : 0, ss = m[6] ? +m[6] : 0;
    if (m[7])
        return new Date(Date.UTC(y, mo, d, hh, mi, ss));
    return new Date(y, mo, d, hh, mi, ss);
}

function parseRule(s) {
    var out = {};
    String(s).split(";").forEach(function (kv) {
        var i = kv.indexOf("=");
        if (i > 0)
            out[kv.slice(0, i).toUpperCase()] = kv.slice(i + 1);
    });
    return out;
}

function addMonths(d, n) {
    var r = new Date(d.getTime());
    var day = r.getDate();
    r.setDate(1);
    r.setMonth(r.getMonth() + n);
    // Clamp: 31 Jan + 1 month is 28/29 Feb, not 2/3 Mar.
    r.setDate(Math.min(day, new Date(r.getFullYear(), r.getMonth() + 1, 0).getDate()));
    return r;
}

function step(d, freq, n) {
    var r = new Date(d.getTime());
    if (freq === "DAILY")
        r.setDate(r.getDate() + n);
    else if (freq === "WEEKLY")
        r.setDate(r.getDate() + 7 * n);
    else if (freq === "MONTHLY")
        return addMonths(r, n);
    else if (freq === "YEARLY")
        r.setFullYear(r.getFullYear() + n);
    else
        return null;
    return r;
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// Every start time this event has inside [from, to].
function occurrences(start, rule, exdates, from, to) {
    var out = [];
    if (!rule || !rule.FREQ) {
        if (start >= from && start <= to)
            out.push(new Date(start.getTime()));
        return out;
    }

    var freq = rule.FREQ.toUpperCase();
    var interval = parseInt(rule.INTERVAL || "1", 10) || 1;
    var count = rule.COUNT ? parseInt(rule.COUNT, 10) : null;
    var until = rule.UNTIL ? parseDate(rule.UNTIL) : null;
    var byday = rule.BYDAY ? rule.BYDAY.split(",").map(function (d) {
        return DAY[d.trim().slice(-2).toUpperCase()];
    }).filter(function (d) {
        return d !== undefined;
    }) : null;

    var emitted = 0;
    var cursor = new Date(start.getTime());

    function consider(when) {
        if (until && when > until)
            return false;
        if (count !== null && emitted >= count)
            return false;
        emitted++;
        var excluded = exdates.some(function (x) {
            return Math.abs(x - when) < 1000 || (sameDay(x, when) && x.getHours() === when.getHours());
        });
        if (!excluded && when >= from && when <= to)
            out.push(new Date(when.getTime()));
        return true;
    }

    for (var guard = 0; guard < MAX_INSTANCES; guard++) {
        if (cursor > to && !(count !== null && emitted < count))
            break;
        if (freq === "WEEKLY" && byday && byday.length) {
            // Walk the week the cursor sits in, Sunday first.
            var weekStart = new Date(cursor.getTime());
            weekStart.setDate(weekStart.getDate() - weekStart.getDay());
            var stop = false;
            for (var i = 0; i < 7 && !stop; i++) {
                if (byday.indexOf(i) === -1)
                    continue;
                var when = new Date(weekStart.getTime());
                when.setDate(weekStart.getDate() + i);
                when.setHours(start.getHours(), start.getMinutes(), start.getSeconds(), 0);
                if (when < start)
                    continue;
                if (!consider(when))
                    stop = true;
            }
            if (stop)
                break;
        } else if (!consider(cursor)) {
            break;
        }
        var next = step(cursor, freq, interval);
        if (!next)
            break;
        cursor = next;
    }
    return out;
}

// Returns [{summary, location, start, end, allDay}], sorted, within [from, to].
function parseEvents(text, from, to) {
    var lines = unfold(String(text)).split("\n");
    var events = [];
    var cur = null;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "BEGIN:VEVENT") {
            cur = {
                summary: "",
                location: "",
                start: null,
                end: null,
                allDay: false,
                rule: null,
                exdates: []
            };
            continue;
        }
        if (!cur)
            continue;
        if (line === "END:VEVENT") {
            if (cur.start) {
                var dur = (cur.end && cur.end > cur.start) ? (cur.end - cur.start) : (cur.allDay ? 86400000 : 3600000);
                occurrences(cur.start, cur.rule, cur.exdates, from, to).forEach(function (s) {
                    events.push({
                        summary: cur.summary || "(no title)",
                        location: cur.location,
                        start: s,
                        end: new Date(s.getTime() + dur),
                        allDay: cur.allDay
                    });
                });
            }
            cur = null;
            continue;
        }

        var sep = line.indexOf(":");
        if (sep < 0)
            continue;
        var head = line.slice(0, sep);
        var value = line.slice(sep + 1);
        var name = head.split(";")[0].toUpperCase();

        if (name === "SUMMARY")
            cur.summary = unescapeText(value);
        else if (name === "LOCATION")
            cur.location = unescapeText(value);
        else if (name === "DTSTART") {
            cur.start = parseDate(value);
            cur.allDay = head.toUpperCase().indexOf("VALUE=DATE") !== -1 && value.indexOf("T") === -1;
        } else if (name === "DTEND")
            cur.end = parseDate(value);
        else if (name === "RRULE")
            cur.rule = parseRule(value);
        else if (name === "EXDATE") {
            value.split(",").forEach(function (v) {
                var d = parseDate(v);
                if (d)
                    cur.exdates.push(d);
            });
        }
    }

    events.sort(function (a, b) {
        return a.start - b.start;
    });
    return events;
}
