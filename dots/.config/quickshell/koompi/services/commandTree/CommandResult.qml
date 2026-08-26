import qs.modules.common.models

/**
 * A Search row that came out of the command tree. It is a LauncherSearchResult,
 * so SearchItem and the panel's keyboard handling treat it exactly like an app
 * or a window row; the three extra fields are the only thing a leaf draws that
 * the other providers do not.
 *
 *   group      the trailing "· Toggles" label on a flat result
 *   heading    the group heading drawn above this row, set on the first row of
 *              each group in the action scope's grouped empty state
 *   stateText  the right-hand state column ("off", "16 px", "3")
 */
LauncherSearchResult {
    property string group: ""
    property string heading: ""
    property string stateText: ""
}
