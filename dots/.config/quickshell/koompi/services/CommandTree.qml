pragma Singleton

import qs.services.commandTree
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Everything the desktop can do to itself, reachable by typing three letters
 * (OMARCHY-AUDIT O05). One flat index of leaves, defined in commandTree/Entries.qml;
 * groups are headings, not levels, so there is no drilling and no back key.
 *
 * LauncherSearch calls `results(query)` once and gets finished Search rows:
 *   - the action scope with nothing after the prefix ("/") -> every available
 *     leaf, in group order, the first row of each group carrying the heading;
 *   - anything else -> the fuzzy matches, each carrying its group as a trailing
 *     label, capped outside the scope so they cannot crowd out the app list.
 *
 * A leaf whose `when` is false is absent, not greyed. Conditions read a
 * property some service already keeps, so a keystroke costs no process; the two
 * that had no home are probed once in commandTree/Conditions.qml.
 */
Singleton {
    id: root

    readonly property Conditions conditions: Conditions {}
    readonly property Entries entries: Entries {
        conditions: root.conditions
    }

    // Re-evaluated whenever a condition's own property changes: the `when`
    // closures are called from inside this binding, so QML captures whatever
    // they read as a dependency.
    readonly property var available: root.entries.all.filter(entry => !entry.when || entry.when())

    // Two indexes, not one: a label hit always outranks a keyword hit, so
    // "nig" answers with Night light and not with the row whose keywords
    // happen to mention the night.
    readonly property var preparedLabels: root.available.map(entry => ({
                name: Fuzzy.prepare(entry.label),
                entry: entry
            }))
    readonly property var preparedKeywords: root.available.map(entry => ({
                name: Fuzzy.prepare(`${entry.label} ${entry.keywords ?? ""}`),
                entry: entry
            }))

    // Every other scope answers for itself, so a query already inside one gets
    // no leaves. Nothing here matches a "$" or a "?" anyway; this says so
    // rather than leaving it to the fuzzy match to be true by accident.
    readonly property var foreignPrefixes: {
        const prefix = Config.options.search.prefix;
        return [prefix.app, prefix.clipboard, prefix.emojis, prefix.file, prefix.math, prefix.settings, prefix.shellCommand, prefix.webSearch, prefix.window];
    }

    // Leaf labels are short, so a subsequence match finds a query in too many of
    // them without a floor, the same problem window titles have.
    readonly property real scoreThreshold: 0.4
    // Outside the action scope the leaves share the list with every app.
    readonly property int flatLimit: 5

    function groupLabel(id: string): string {
        return root.entries.groups.find(group => group.id === id)?.label ?? "";
    }

    function matches(search: string): var {
        const go = index => Fuzzy.go(search, index, {
            all: true,
            key: "name",
            threshold: root.scoreThreshold
        }).map(result => result.obj.entry);
        const byLabel = go(root.preparedLabels);
        return byLabel.concat(go(root.preparedKeywords).filter(entry => !byLabel.includes(entry)));
    }

    function rowFor(entry, heading: string, showGroup: bool): var {
        return rowComp.createObject(null, {
            id: entry.id,
            name: entry.label,
            verb: entry.verb ?? Translation.tr("Run"),
            iconName: entry.icon,
            iconType: LauncherSearchResult.IconType.Material,
            group: showGroup ? root.groupLabel(entry.group) : "",
            heading: heading,
            stateText: entry.state ? entry.state() : "",
            execute: entry.execute
        });
    }

    // Group order is the order they are declared in, and a group with nothing
    // available contributes no heading.
    function groupedResults(): var {
        let rows = [];
        for (const group of root.entries.groups) {
            const inGroup = root.available.filter(entry => entry.group === group.id);
            for (let i = 0; i < inGroup.length; i++) {
                rows.push(root.rowFor(inGroup[i], i === 0 ? group.label : "", false));
            }
        }
        return rows;
    }

    function results(query: string): var {
        const prefix = Config.options.search.prefix.action;
        const scoped = query.startsWith(prefix);
        const search = scoped ? query.slice(prefix.length) : query;
        if (!scoped && root.foreignPrefixes.some(other => query.startsWith(other)))
            return [];
        // An empty unprefixed query is the panel's recent-apps view and stays it.
        if (search.trim() === "")
            return scoped ? root.groupedResults() : [];
        const hits = root.matches(search);
        return (scoped ? hits : hits.slice(0, root.flatLimit)).map(entry => root.rowFor(entry, "", true));
    }

    Component {
        id: rowComp
        CommandResult {}
    }
}
