.pragma library

// Where a swipe should leave the grid.
//
// Split out of the pager so the feel of it can be reasoned about, and checked,
// without a touchpad in hand. Everything is counted in pages: `start` is where
// the gesture began, `position` where it let go, both fractional, and
// `velocity` is how fast the strip was still moving in pixels per second,
// positive towards later pages.
//
// Three ways to land somewhere new, in order of precedence:
//
//   a flick   still moving when released, so it carries a page in the direction
//             of travel however short it was. This is the one that makes a
//             quick, small gesture work.
//   a drag    slow, but far enough into the next page to have meant it.
//   neither   springs back to where it started.
function settleTarget(start, position, velocity, pageCount, opts) {
    const settleFraction = opts.settleFraction;
    const flickVelocity = opts.flickVelocity;

    const base = Math.round(start);
    const travelled = position - base;
    // Whole pages crossed, and how far into the one after them.
    const whole = Math.trunc(travelled);
    const frac = travelled - whole;

    let target;
    if (Math.abs(velocity) > flickVelocity)
        target = base + (velocity > 0 ? Math.floor(travelled) + 1 : Math.ceil(travelled) - 1);
    // The epsilon is not superstition: subtracting the base leaves 1.78 - 2 at
    // -0.21999999999999997, so without it the same gesture pages forwards and
    // refuses to page back.
    else if (Math.abs(frac) >= settleFraction - 1e-9)
        target = base + whole + (frac > 0 ? 1 : -1);
    else
        target = base + whole;

    return Math.max(0, Math.min(pageCount - 1, target));
}

// Resistance past the first and last page, so an overscroll answers back
// instead of hitting a wall.
function resist(x, minX, maxX, rubberBand) {
    if (x > maxX)
        return maxX + (x - maxX) * rubberBand;
    if (x < minX)
        return minX + (x - minX) * rubberBand;
    return x;
}

// Whole wheel notches out of an accumulated angle delta, and what is left over.
// High-resolution wheels send fractions of a notch, so they have to add up
// rather than be counted. Returns [pages, remainder]; a positive delta pages
// backwards, matching every other horizontal scroll on the desktop.
function notchSteps(accumulated) {
    let steps = 0;
    let rest = accumulated;
    while (Math.abs(rest) >= 120) {
        steps += rest > 0 ? -1 : 1;
        rest += rest > 0 ? -120 : 120;
    }
    return [steps, rest];
}
