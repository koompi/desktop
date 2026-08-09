// sunrise equation, https://en.wikipedia.org/wiki/Sunrise_equation

const DEG = Math.PI / 180;

function sinDeg(d) {
    return Math.sin(d * DEG);
}

function cosDeg(d) {
    return Math.cos(d * DEG);
}

function wrapDeg(d) {
    return ((d % 360) + 360) % 360;
}

function toJulian(date) {
    return date.getTime() / 86400000 + 2440587.5;
}

function fromJulian(julian) {
    return new Date((julian - 2440587.5) * 86400000);
}

function sunTimes(date, latitude, longitude) {
    const westward = -longitude;
    const cycle = Math.round(toJulian(date) - 2451545.0 - 0.0009 - westward / 360);
    const meanNoon = 2451545.0 + 0.0009 + westward / 360 + cycle;

    const anomaly = wrapDeg(357.5291 + 0.98560028 * (meanNoon - 2451545.0));
    const center = 1.9148 * sinDeg(anomaly) + 0.02 * sinDeg(2 * anomaly) + 0.0003 * sinDeg(3 * anomaly);
    const eclipticLongitude = wrapDeg(anomaly + center + 180 + 102.9372);

    const transit = meanNoon + 0.0053 * sinDeg(anomaly) - 0.0069 * sinDeg(2 * eclipticLongitude);
    const declination = Math.asin(sinDeg(eclipticLongitude) * sinDeg(23.44)) / DEG;
    const hourAngle = (sinDeg(-0.833) - sinDeg(latitude) * sinDeg(declination)) / (cosDeg(latitude) * cosDeg(declination));

    if (hourAngle < -1)
        return { sunrise: null, sunset: null, transit: fromJulian(transit), alwaysUp: true, alwaysDown: false };
    if (hourAngle > 1)
        return { sunrise: null, sunset: null, transit: fromJulian(transit), alwaysUp: false, alwaysDown: true };

    const halfDay = Math.acos(hourAngle) / DEG / 360;
    return {
        sunrise: fromJulian(transit - halfDay),
        sunset: fromJulian(transit + halfDay),
        transit: fromJulian(transit),
        alwaysUp: false,
        alwaysDown: false
    };
}
