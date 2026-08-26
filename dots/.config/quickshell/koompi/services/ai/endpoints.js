.pragma library

// Where an endpoint's host lives, read from its URL. Loopback is "local": it
// decides policies.ai == 2 and whether a model needs a key. Self-hosted adds the
// private ranges, a bare hostname and *.local: it decides the fallback window,
// since a box on the LAN is not a 128k hosted model.

function hostOf(url) {
    const m = /^(?:[a-z][a-z0-9+.-]*:\/\/)?(?:[^@\/]*@)?(\[[^\]]*\]|[^:\/?#]+)/i.exec(`${url ?? ""}`.trim());
    return m ? m[1].toLowerCase() : "";
}

function isLocal(url) {
    const host = hostOf(url);
    return host === "localhost" || host === "127.0.0.1" || host === "[::1]";
}

function isSelfHosted(url) {
    const host = hostOf(url);
    if (host.length === 0) return false;
    return isLocal(url)
        || host.endsWith(".local")
        || host.indexOf(".") < 0
        || /^10\.\d+\.\d+\.\d+$/.test(host)
        || /^192\.168\.\d+\.\d+$/.test(host)
        || /^172\.(1[6-9]|2\d|3[01])\.\d+\.\d+$/.test(host);
}
