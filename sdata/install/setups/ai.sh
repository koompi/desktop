# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The sidebar local model (LiteRT-LM) and the loopback SearXNG behind search_web.

# The sidebar's local model runs on LiteRT-LM, which serves an OpenAI-compatible
# API on 127.0.0.1:9379. The CLI and the config land on every install; the 2.6 GB
# of weights are asked for, because a desktop install has no business pulling
# that down uninvited.
readonly LOCAL_AI_MODEL_ID=gemma4-e2b
readonly LOCAL_AI_MODEL_REPO=litert-community/gemma-4-E2B-it-litert-lm
readonly LOCAL_AI_MODEL_FILE=gemma-4-E2B-it.litertlm

setup_local_ai() {
    step "Local AI"
    if ! have uv; then
        warn "uv not found; the sidebar's local model will have nothing to talk to"
        return 0
    fi

    export PATH="$XDG_BIN_HOME:$PATH"
    if have litert-lm; then
        # serve(1) only exists from v0.13. An older pin looks like a missing feature.
        run uv tool upgrade litert-lm
    else
        run uv tool install litert-lm
    fi
    write_litert_lm_config

    if [[ "$DRY_RUN" != true ]] && ! litert-lm list 2>/dev/null | grep -q "$LOCAL_AI_MODEL_ID"; then
        printf '\n  The sidebar answers offline once a model is on disk.\n'
        printf '  %s is a 2.6 GB download.\n\n' "$LOCAL_AI_MODEL_ID"
        if confirm "Download it now? (no = the sidebar stays on its remote model)"; then
            run litert-lm import --from-huggingface-repo "$LOCAL_AI_MODEL_REPO" \
                "$LOCAL_AI_MODEL_FILE" "$LOCAL_AI_MODEL_ID"
        else
            info "skipped; run 'litert-lm import --from-huggingface-repo $LOCAL_AI_MODEL_REPO $LOCAL_AI_MODEL_FILE $LOCAL_AI_MODEL_ID' when you want it"
            return 0
        fi
    fi

    if ! systemd_user_running; then
        warn "no user systemd manager here; enable litert-lm.socket after your next login"
    else
        # the socket only: litert-lm and its watchdog are pulled in on the first
        # request and released again once the sidebar has been shut for 5min
        run systemctl --user enable litert-lm.socket
        # an install from before the socket wanted these off
        # graphical-session.target, which pins the engine for the whole session
        # and leaves StopWhenUnneeded nothing to act on
        run systemctl --user disable litert-lm.service litert-lm-watchdog.service
    fi

    setup_local_search
}

# The sidebar's search_web tool. Every free engine blocks a scraper, so the
# lookup goes through a SearXNG of our own on loopback: no API key, and the
# queries do not leave the machine to a third party.
readonly SEARXNG_PORT=8888

setup_local_search() {
    local runtime=""
    have docker && runtime=docker
    [[ -z "$runtime" ]] && have podman && runtime=podman
    if [[ -z "$runtime" ]]; then
        warn "no docker or podman; the sidebar can still read URLs but search_web will be dead"
        return 0
    fi

    local conf="$XDG_CONFIG_HOME/searxng"
    if [[ ! -f "$conf/settings.yml" ]]; then
        run mkdir -p "$conf"
        if [[ "$DRY_RUN" != true ]]; then
            # json is not in the default formats list, and the tool speaks only json
            cat > "$conf/settings.yml" <<EOF
use_default_settings: true

general:
  instance_name: "KOOMPI local search"
  donation_url: false
  contact_url: false

server:
  secret_key: "$(head -c 32 /dev/urandom | base64 | tr -d '\n/+=' | head -c 32)"
  limiter: false
  public_instance: false
  image_proxy: false
  method: "GET"

search:
  safe_search: 0
  autocomplete: ""
  default_lang: "all"
  formats:
    - html
    - json

ui:
  static_use_hash: true
EOF
        fi
    fi

    if [[ "$DRY_RUN" != true ]] && "$runtime" inspect searxng >/dev/null 2>&1; then
        info "searxng container already present"
        return 0
    fi
    run "$runtime" run -d --name searxng --restart unless-stopped \
        -p "127.0.0.1:$SEARXNG_PORT:8080" \
        -v "$conf:/etc/searxng" \
        -e "SEARXNG_BASE_URL=http://127.0.0.1:$SEARXNG_PORT/" \
        docker.io/searxng/searxng:latest
}

# Written rather than shipped through dots/ because ~/.litert-lm is the CLI's own
# directory and holds the imported models beside it.
#
# The key is `default`. `global_defaults` reads like the right name, and the
# schema sets additionalProperties:true, so a wrong top-level key is accepted in
# silence and nothing under it ever applies. The server logs "Using <field> from
# config" at engine init; that line is the only proof it landed.
#
# max_num_tokens has to clear the 4096 default: one get_shell_config turn is
# already 6155 tokens and fails the whole request as too long.
write_litert_lm_config() {
    local config="$HOME/.litert-lm/config.json"
    [[ -e "$config" ]] && { info "$config exists; leaving it alone"; return 0; }
    [[ "$DRY_RUN" == true ]] && { info "would write $config"; return 0; }

    mkdir -p "$(dirname "$config")"
    cat > "$config" <<'EOF'
{
  "default": {
    "backend": "gpu",
    "cpu_thread_count": 8,
    "cache": "disk",
    "max_num_tokens": 16384
  }
}
EOF
    manifest_add "$config"
    ok "wrote $config"
}
