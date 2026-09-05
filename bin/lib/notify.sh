#!/usr/bin/bash
#
# Shared Discord notify helpers for bin/ scripts and .gitlab-ci.yml jobs.
# uBix Core posts to
# Discord webhooks instead. Source it:
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
#   . "$SCRIPT_DIR/bin/lib/notify.sh"
#
# Webhook resolution order for channel <name> (ops | alerts | reviews):
#   1. env DISCORD_<NAME>_WEBHOOK_URL            (local / manual override)
#   2. ubixvault KV secret/ubixcore/discord.<name>_webhook_url, read with the
#      read-only CI token: UBIXVAULT_CI_TOKEN_DEV for the dev branch/vault,
#      UBIXVAULT_CI_TOKEN_PROD for staging/main (GitLab masked variables).
# A missing webhook or a failed POST never affects the caller (exit 0).

UBIXVAULT_ADDR_DEV="${UBIXVAULT_ADDR_DEV:-https://vault.dev.ubixsys.com}"
UBIXVAULT_ADDR_PROD="${UBIXVAULT_ADDR_PROD:-https://vault.prod.ubixsys.com}"

# Escape a string for embedding inside a JSON string value (no jq dependency).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/ }"
    s="${s//$'\r'/}"
    printf '%s' "$s"
}

# Which vault + token serve this pipeline/branch. Arg: branch/env name
# (defaults to CI_COMMIT_REF_NAME, then the current git branch).
vault_for_branch() {
    local ref="${1:-${CI_COMMIT_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}}"
    case "$ref" in
        main|master|staging)
            VAULT_ADDR="$UBIXVAULT_ADDR_PROD"; VAULT_TOKEN="${UBIXVAULT_CI_TOKEN_PROD:-}" ;;
        *)
            VAULT_ADDR="$UBIXVAULT_ADDR_DEV";  VAULT_TOKEN="${UBIXVAULT_CI_TOKEN_DEV:-}" ;;
    esac
}

# vault_kv <path-under-secret/<project>> <key> — prints the value from
# secret/${VAULT_KV_PREFIX:-${CI_PROJECT_NAME:-app}}/<path> via the branch's read-only CI token, or nothing.
vault_kv() {
    local path="$1" key="$2"
    vault_for_branch
    [ -n "${VAULT_TOKEN:-}" ] || return 0
    curl -sS -m 10 -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/${VAULT_KV_PREFIX:-${CI_PROJECT_NAME:-app}}/${path}" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['data'].get('${key}',''))" 2>/dev/null \
        || true
}

# discord_webhook <ops|alerts|reviews> — prints the URL or nothing.
discord_webhook() {
    local name="$1" upper url
    upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    url="$(printenv "DISCORD_${upper}_WEBHOOK_URL" 2>/dev/null || true)"
    if [ -n "$url" ]; then printf '%s' "$url"; return 0; fi
    vault_for_branch
    [ -n "${VAULT_TOKEN:-}" ] || return 0
    curl -sS -m 10 -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/ubixcore/discord" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['data'].get('${name}_webhook_url',''))" 2>/dev/null \
        || true
}

# discord <ops|alerts|reviews> <color-hex-int> <title> <text>
# Posts one embed. color: 3066993 green · 15158332 red · 15105570 orange · 3447003 blue.
discord() {
    local channel="$1" color="$2" title="$3" text="$4" url payload
    url="$(discord_webhook "$channel")"
    if [ -z "$url" ]; then
        echo "No Discord webhook for #ubixcore-${channel} — skipping notify"
        return 0
    fi
    payload="{\"username\":\"uBix Core\",\"embeds\":[{\"title\":\"$(json_escape "$title")\",\"description\":\"$(json_escape "$text")\",\"color\":${color}}]}"
    curl -sS -m 10 -X POST -H 'Content-Type: application/json' --data "$payload" "$url" >/dev/null 2>&1 \
        && echo "Posted to #ubixcore-${channel}" \
        || echo "Discord notify failed for #ubixcore-${channel} (ignored)"
    return 0
}
