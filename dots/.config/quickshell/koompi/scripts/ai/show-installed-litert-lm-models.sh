#!/usr/bin/env bash

# Ask the running server rather than `litert-lm list`: it answers with exactly
# what it will serve, and a model the server cannot load is not one the picker
# should offer. No server, no local models.
curl -sf -m 2 http://127.0.0.1:9379/v1/models 2>/dev/null \
    | jq -c '[.data[].id]' 2>/dev/null \
    || echo '[]'
