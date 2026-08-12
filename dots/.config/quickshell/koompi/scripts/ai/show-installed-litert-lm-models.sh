#!/usr/bin/env bash

# Ask the running server rather than `litert-lm list`: it answers with exactly
# what it will serve, and a model the server cannot load is not one the picker
# should offer. No server, no local models.
#
# 10s, not 2s: 9379 is a socket-activated unit, so this call is what wakes the
# server. A cold wake measured ~1s and an empty answer here empties the picker
# for the session.
curl -sf -m 10 http://127.0.0.1:9379/v1/models 2>/dev/null \
    | jq -c '[.data[].id]' 2>/dev/null \
    || echo '[]'
