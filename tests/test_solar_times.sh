#!/usr/bin/env bash
# Auto light/dark switches on computed sunrise and sunset, so a sign error or a
# bad hour angle would leave a laptop dark at noon and nobody would know why.
# Runs services/solar.js under bun against physical invariants (equinox day
# length, polar day and night, symmetry about solar noon) plus one published
# anchor, and checks the timezone lookup the service feeds it. No network.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOLAR_JS="$REPO_ROOT/dots/.config/quickshell/koompi/services/solar.js"
COORDS_SH="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/timezone-coords.sh"

[[ -f "$SOLAR_JS" ]] || { echo "missing $SOLAR_JS" >&2; exit 1; }
[[ -f "$COORDS_SH" ]] || { echo "missing $COORDS_SH" >&2; exit 1; }

failed=0

# The service parses this into a latitude and longitude, so a table miss or a
# format it cannot read means auto mode silently falls back to fixed hours.
coords="$(bash "$COORDS_SH")"
if [[ -z "$coords" ]]; then
    echo "FAIL: timezone-coords.sh printed nothing for $(readlink -f /etc/localtime)" >&2
    failed=1
elif [[ ! "$coords" =~ ^[+-][0-9]{4}([0-9]{2})?[+-][0-9]{5}([0-9]{2})?$ ]]; then
    echo "FAIL: timezone-coords.sh printed unparseable '$coords'" >&2
    failed=1
fi

command -v bun >/dev/null || {
    echo "bun not installed; skipping the solar checks" >&2
    exit $failed
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$SOLAR_JS" "$tmp/solar.js"
# The file is QML-flavoured JS with no exports; expose its function to the test.
printf '\nexport { sunTimes };\n' >> "$tmp/solar.js"

cat > "$tmp/run.mjs" <<'EOF'
import { sunTimes } from "./solar.js";

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};
const at = (iso, lat, lon) => sunTimes(new Date(iso), lat, lon);
const hours = (a, b) => (b - a) / 3600000;
const utc = d => d.toISOString().slice(11, 16);

// Day and night are equal everywhere at the equinox. Refraction and the sun's
// disc push it a little past twelve hours, more so towards the poles.
for (const lat of [0, 20, 40, 60]) {
    const s = at("2026-03-20T12:00:00Z", lat, 0);
    const length = hours(s.sunrise, s.sunset);
    check(`equinox day length at ${lat}N`, length > 12 && length < 12.4, `got ${length.toFixed(2)}h`);
}
const southern = at("2026-03-20T12:00:00Z", -40, 0);
check("equinox day length at 40S", Math.abs(hours(southern.sunrise, southern.sunset) - 12.15) < 0.25);

// Sunrise at the intersection of the equator and the prime meridian is the one
// case with no timezone or longitude offset to reason about: near 06:00 UTC.
const origin = at("2026-03-20T12:00:00Z", 0, 0);
check("equinox sunrise at 0N 0E is near 06:00Z", Math.abs(hours(new Date("2026-03-20T06:00:00Z"), origin.sunrise)) < 0.2, `got ${utc(origin.sunrise)}`);

// Published: London, 21 June 2026, sunrise 04:43 BST and sunset 21:21 BST.
const london = at("2026-06-21T12:00:00Z", 51.5074, -0.1278);
check("London solstice sunrise", Math.abs(hours(new Date("2026-06-21T03:43:00Z"), london.sunrise)) < 0.09, `got ${utc(london.sunrise)}Z`);
check("London solstice sunset", Math.abs(hours(new Date("2026-06-21T20:21:00Z"), london.sunset)) < 0.09, `got ${utc(london.sunset)}Z`);

// Above the Arctic Circle the sun neither sets in June nor rises in December.
// Without these flags the hour angle is out of range and every time is NaN.
const tromsoJune = at("2026-06-21T12:00:00Z", 69.65, 18.96);
check("Tromso is polar day in June", tromsoJune.alwaysUp && !tromsoJune.alwaysDown && tromsoJune.sunrise === null);
const tromsoDecember = at("2026-12-21T12:00:00Z", 69.65, 18.96);
check("Tromso is polar night in December", tromsoDecember.alwaysDown && !tromsoDecember.alwaysUp && tromsoDecember.sunset === null);

// Sunrise and sunset sit either side of solar noon by the same amount.
for (const [lat, lon] of [[11.55, 104.9167], [51.5, -0.13], [-33.87, 151.21]]) {
    const s = at("2026-08-09T12:00:00Z", lat, lon);
    const midpoint = new Date((s.sunrise.getTime() + s.sunset.getTime()) / 2);
    check(`transit is midway at ${lat},${lon}`, Math.abs(hours(midpoint, s.transit)) < 0.02, `off by ${(hours(midpoint, s.transit) * 60).toFixed(1)}min`);
}

// Seasons invert across the equator.
const sydneyJune = at("2026-06-21T02:00:00Z", -33.87, 151.21);
const sydneyDecember = at("2026-12-21T02:00:00Z", -33.87, 151.21);
check("Sydney days are longer in December than June",
    hours(sydneyDecember.sunrise, sydneyDecember.sunset) - hours(sydneyJune.sunrise, sydneyJune.sunset) > 4);

// Fifteen degrees of longitude is an hour of solar time.
const east = at("2026-08-09T12:00:00Z", 0, 0);
const west = at("2026-08-09T12:00:00Z", 0, -15);
check("15 degrees west delays sunrise by an hour", Math.abs(hours(east.sunrise, west.sunrise) - 1) < 0.02);

// A whole year without a NaN, at latitudes where the formula is well behaved.
for (let day = 0; day < 365; day += 7) {
    const date = new Date(Date.UTC(2026, 0, 1 + day, 12));
    const s = sunTimes(date, 11.55, 104.9167);
    check(`sun times are finite on day ${day}`, s.sunrise instanceof Date && !isNaN(s.sunrise.getTime()) && s.sunset > s.sunrise);
}

if (failed > 0) {
    console.error(`${failed} check(s) failed`);
    process.exit(1);
}
EOF

(cd "$tmp" && bun run.mjs) || failed=1

exit $failed
