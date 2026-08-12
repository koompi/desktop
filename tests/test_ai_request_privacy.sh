#!/usr/bin/env bash
# Everything the assistant hands to a shell carries the conversation: the request
# body, the summariser's script, an attached screenshot. All three used to land in
# /tmp/quickshell/ai, which on a default umask is world-readable, and a 36 KB
# compact.sh holding a real conversation was found there at 0644 while this was
# being written. A screen grab and a clipboard decode are no less private, and
# they were still in /tmp/quickshell/media a leak later. Nothing the shell writes
# belongs under a prefix another uid can read, or squat before the shell boots.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { echo "$1" >&2; exit 1; }

[[ -d "$SHELL_ROOT" ]] || fail "missing $SHELL_ROOT"

# No path under the shell's own /tmp prefix, anywhere. A comment naming it is how
# the two fixes explain themselves, so only code counts.
offenders="$(grep -rn '/tmp/quickshell' "$SHELL_ROOT" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*//' \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*#')"
if [[ -n "$offenders" ]]; then
    echo "the shell writes into shared /tmp:" >&2
    echo "$offenders" >&2
    exit 1
fi

# The two script paths derive from XDG_RUNTIME_DIR, which systemd creates at 0700.
grep -q 'Quickshell.env("XDG_RUNTIME_DIR")' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "Requester.qml no longer derives its script directory from XDG_RUNTIME_DIR"
grep -q 'requester.scriptDirPath' "$SHELL_ROOT/services/ai/Conversation.qml" \
    || fail "the compactor script no longer sits beside the request body"
grep -q 'Quickshell.env("XDG_RUNTIME_DIR")' "$SHELL_ROOT/modules/common/Directories.qml" \
    || fail "Directories.aiAttach no longer derives from XDG_RUNTIME_DIR"

# curl reads the script through a wrapper that narrows it first, because the file
# exists between setText and exec whatever the directory permits.
for file in services/ai/Requester.qml services/ai/Conversation.qml; do
    grep -q 'chmod 600' "$SHELL_ROOT/$file" \
        || fail "$file runs its script without chmodding it to 0600 first"
done

# The directories are created narrow rather than left to the login umask.
grep -q '"mkdir", "-p", "-m", "700"' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "the request script directory is no longer created at 0700"
# attach sits under the shared ai dir, so its parent is the one that has to be
# narrow: -m would mode the leaf and leave the parent at 755.
grep -q "umask 077; mkdir -p '\${aiAttach}' && chmod 700 '\${aiRuntime}'" \
    "$SHELL_ROOT/modules/common/Directories.qml" \
    || fail "the attachment directory's parent is no longer created and repaired at 0700"

# Screen grabs, clipboard decodes and downloaded images share one runtime root, so
# one binding decides whether any of them can be read by another uid.
grep -q 'runtimeMedia' "$SHELL_ROOT/modules/common/Directories.qml" \
    || fail "Directories no longer routes its media temp dirs through runtimeMedia"
for prop in tempImages cliphistDecode screenshotTemp; do
    grep -qE "property string $prop: \`\\\$\{Directories.runtimeMedia\}" \
        "$SHELL_ROOT/modules/common/Directories.qml" \
        || fail "Directories.$prop no longer derives from runtimeMedia"
done

# mkdir -p -m applies the mode to the leaf only, so the creators that can win the
# race to make the shared parent set a umask instead.
for file in modules/common/utils/TempScreenshotProcess.qml \
            modules/common/models/gCloud/GCloudVision.qml \
            modules/common/Directories.qml \
            scripts/ai/gemini-categorize-wallpaper.sh; do
    grep -q 'umask 077' "$SHELL_ROOT/$file" \
        || fail "$file creates a media directory without narrowing the umask first"
done

# The API key rides in the environment; a key written into the script file would
# survive on disk for anything that can read it.
literal="$(grep -rn 'Authorization: Bearer' "$SHELL_ROOT/services/ai/" | grep -v 'apiKeyEnvVarName')"
if [[ -n "$literal" ]]; then
    echo "an API key is written into the request script rather than read from the environment:" >&2
    echo "$literal" >&2
    exit 1
fi

echo "ok: request body, compactor, attachments, screen grabs and clipboard decodes stay in the user's runtime directory"
