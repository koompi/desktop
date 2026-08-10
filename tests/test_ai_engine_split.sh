#!/usr/bin/env bash
# The AI engine lives in services/ai/ but the UI only ever talks to the Ai singleton.
# This derives the list of names the UI touches by grepping `Ai.` across modules/ and
# fails if any of them stopped being declared on Ai.qml, which is what a split that
# leaked its internals would look like.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
FACADE="$SHELL_ROOT/services/Ai.qml"
MODULES="$SHELL_ROOT/modules"

[[ -f "$FACADE" ]] || { echo "missing $FACADE" >&2; exit 1; }
[[ -d "$MODULES" ]] || { echo "missing $MODULES" >&2; exit 1; }

mapfile -t used < <(grep -rho 'Ai\.[a-zA-Z_][a-zA-Z0-9_]*' "$MODULES" | sed 's/^Ai\.//' | sort -u)

(( ${#used[@]} > 0 )) || { echo "no Ai.* references found under $MODULES" >&2; exit 1; }

# Anything the facade declares itself: a property, a function or a signal.
declared="$(grep -oE '^[[:space:]]*(readonly[[:space:]]+)?property[[:space:]]+[A-Za-z_][A-Za-z0-9_]*(<[^>]*>)?[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*' "$FACADE" \
    | awk '{print $NF}')
$(grep -oE '^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*' "$FACADE" | awk '{print $NF}')
$(grep -oE '^[[:space:]]*signal[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*' "$FACADE" | awk '{print $NF}')"

missing=()
for name in "${used[@]}"; do
    grep -qxF "$name" <<< "$declared" || missing+=("$name")
done

if (( ${#missing[@]} > 0 )); then
    printf 'Ai.qml no longer declares a name the UI calls:\n' >&2
    printf '  Ai.%s\n' "${missing[@]}" >&2
    exit 1
fi

# The split itself: the engine is four modules plus the model layer, and Ai.qml is
# the only thing modules/ is allowed to know about.
for module in ToolRegistry ToolRunner Conversation Requester ModelRegistry; do
    [[ -f "$SHELL_ROOT/services/ai/$module.qml" ]] || {
        echo "missing services/ai/$module.qml" >&2; exit 1; }
    if grep -rq "\\b$module\\b" "$MODULES"; then
        echo "modules/ reaches past the facade into $module" >&2; exit 1
    fi
done

# One declaration per tool. Three copies is what the split removed.
for tool in get_shell_config set_shell_config run_shell_command set_owner_name remember recall; do
    count="$(grep -c "\"name\": \"$tool\"" "$SHELL_ROOT/services/ai/ToolRegistry.qml")"
    (( count == 1 )) || { echo "$tool declared $count times in ToolRegistry.qml, expected 1" >&2; exit 1; }
done

echo "ok: ${#used[@]} Ai.* names reachable, 6 tools declared once each"
