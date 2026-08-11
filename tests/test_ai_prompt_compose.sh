#!/usr/bin/env bash
# The system prompt is composed from the ordered files under
# defaults/ai/prompts/system/ rather than living in a string literal inside
# Config.qml. This rebuilds it the way Config.recomposeSystemPrompt does, checks
# it against the committed digest, and checks that every {PLACEHOLDER} left in it
# is one the engine actually substitutes - a section naming a placeholder nobody
# fills would ship "{HOSTNAME}" straight to the model.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
CONFIG="$SHELL_ROOT/modules/common/Config.qml"
ENGINE="$SHELL_ROOT/services/Ai.qml"
SECTION_DIR="$SHELL_ROOT/defaults/ai/prompts/system"

# The committed expectation. Both numbers move only on a deliberate prompt
# change, and a deliberate prompt change is one that was re-tested against
# gemma4-e4b - see .work/J11-report.md for the A/B that set them.
EXPECTED_SHA256=6a26708755832051c128040a314dc8067644089c1daa030beb62588f1df45a2c
EXPECTED_CHARS=3426

# gemma4-e4b corrupts numbers it relays once enough bytes ride along with the
# request; the shipped tool array is already 3900 of them. The prompt shares that
# budget, so growth past this is a decision, not an accident.
MAX_CHARS=4000

fail() { printf '%s\n' "$*" >&2; exit 1; }

[[ -f "$CONFIG" ]] || fail "missing $CONFIG"
[[ -f "$ENGINE" ]] || fail "missing $ENGINE"
[[ -d "$SECTION_DIR" ]] || fail "missing $SECTION_DIR"

# The order comes from Config.qml, so the test cannot drift from the shell.
mapfile -t sections < <(
    sed -n '/readonly property list<string> promptSectionFiles: \[/,/\]/p' "$CONFIG" \
        | grep -oE '"[^"]+\.md"' | tr -d '"'
)
(( ${#sections[@]} > 0 )) || fail "Config.qml declares no promptSectionFiles"

# D38: the literal is gone. Any string property in Config.qml over 1 KB is the
# old 4 KB prompt creeping back in.
if grep -nE 'property string [a-zA-Z]+: "[^"]{1024,}' "$CONFIG"; then
    fail "Config.qml carries a kilobyte-long string literal again"
fi
grep -qE 'property string systemPrompt: root\.composedSystemPrompt' "$CONFIG" \
    || fail "options.ai.systemPrompt no longer binds to the composed prompt"

composed=""
for name in "${sections[@]}"; do
    path="$SECTION_DIR/$name"
    [[ -f "$path" ]] || fail "Config.qml lists $name but $path does not exist"
    body="$(< "$path")"
    # Same String.trim() + "\n\n" join + trailing newline as recomposeSystemPrompt().
    body="${body#"${body%%[![:space:]]*}"}"
    body="${body%"${body##*[![:space:]]}"}"
    [[ -n "$body" ]] || fail "$name is empty"
    if [[ -n "$composed" ]]; then composed+=$'\n\n'; fi
    composed+="$body"
done
composed+=$'\n'

# Every stray file in the directory is a section nobody composes: either list it
# or delete it, because a prompt section that is never read is the D38 bug again.
for path in "$SECTION_DIR"/*; do
    name="$(basename -- "$path")"
    printf '%s\n' "${sections[@]}" | grep -qxF "$name" \
        || fail "$name sits in $SECTION_DIR but Config.qml never composes it"
done

chars="${#composed}"
sha="$(printf '%s' "$composed" | sha256sum | cut -d' ' -f1)"

(( chars <= MAX_CHARS )) || fail "the composed prompt is $chars chars, over the ${MAX_CHARS} budget"

if [[ "$sha" != "$EXPECTED_SHA256" || "$chars" != "$EXPECTED_CHARS" ]]; then
    fail "$(printf 'the composed system prompt changed.\n  expected %s (%s chars)\n  got      %s (%s chars)\nRe-test against gemma4-e4b, then update EXPECTED_SHA256 and EXPECTED_CHARS here.' \
        "$EXPECTED_SHA256" "$EXPECTED_CHARS" "$sha" "$chars")"
fi

# Every placeholder the prompt uses has to be a key the engine fills in.
mapfile -t used < <(grep -oE '\{[A-Z_]+\}' <<< "$composed" | sort -u)
(( ${#used[@]} > 0 )) || fail "the composed prompt names no substitutions at all"

mapfile -t supplied < <(grep -oE '"\{[A-Z_]+\}"' "$ENGINE" | tr -d '"' | sort -u)
(( ${#supplied[@]} > 0 )) || fail "no promptSubstitutions keys found in $ENGINE"

unresolvable=()
for key in "${used[@]}"; do
    printf '%s\n' "${supplied[@]}" | grep -qxF "$key" || unresolvable+=("$key")
done
(( ${#unresolvable[@]} == 0 )) \
    || fail "$(printf 'the prompt uses placeholders nothing substitutes:\n%s\n' "$(printf '  %s\n' "${unresolvable[@]}")")"

# And with every one of them filled, nothing shaped like a placeholder survives.
resolved="$composed"
for key in "${used[@]}"; do
    resolved="${resolved//$key/x}"
done
if grep -qE '\{[A-Z_]+\}' <<< "$resolved"; then
    fail "$(printf 'a placeholder survived substitution:\n%s\n' "$(grep -oE '\{[A-Z_]+\}' <<< "$resolved" | sort -u)")"
fi

printf 'ok: %d sections, %d chars, %d substitutions, all resolvable\n' \
    "${#sections[@]}" "$chars" "${#used[@]}"
