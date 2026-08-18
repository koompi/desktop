"use strict";

const fs = require("fs");

function loadFuzzySort(path) {
    const src = fs.readFileSync(path, "utf8").replace(/^\.pragma library\r?\n/, "");
    const fn = new Function(`${src}\nreturn { go, prepare, cleanup };`);
    return fn();
}

function loadLevendist(path) {
    const src = fs.readFileSync(path, "utf8");
    const fn = new Function(`${src}\nreturn { computeScore, computeTextMatchScore };`);
    return fn();
}

module.exports = { loadFuzzySort, loadLevendist };
