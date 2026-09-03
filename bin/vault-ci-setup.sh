#!/usr/bin/env bash
# One-time uBixVault setup for this project's pipeline. Run it once per Vault
# (dev, prod) with an admin token in the environment - never write the token
# into a file:
#
#   VAULT_TOKEN=<admin> VAULT_ADDR=https://vault.dev.example.com  ./bin/vault-ci-setup.sh dev  myproject
#   VAULT_TOKEN=<admin> VAULT_ADDR=https://vault.prod.example.com ./bin/vault-ci-setup.sh prod myproject
#
# It creates a read-only policy <project>-ci-ro over secret/<project>/*, seeds
# secret/<project>/{test-db,discord,composer} from the values you export (see
# below), and mints a CI token with that policy. Add the printed token as a
# masked CI/CD variable (UBIXVAULT_CI_TOKEN_DEV / _PROD) on the project.
# See docs/ci-setup.md for the full list of what the pipeline needs.
set -euo pipefail

VAULT_TOKEN='uv.872a7fe23ff04f5809e5c9a35fb602194bae1e6d09e12276'        # <- from your password manager (vault.<env> root/admin token)

ENV="${1:?usage: $0 dev|prod}"
case "$ENV" in
  dev)  V=https://vault.dev.ubixsys.com;  VAR=UBIXVAULT_CI_TOKEN_DEV ;;
  prod) V=https://vault.prod.ubixsys.com; VAR=UBIXVAULT_CI_TOKEN_PROD ;;
  *) echo "env must be dev or prod"; exit 1 ;;
esac
[ "$VAULT_TOKEN" != 'PASTE-ADMIN-TOKEN-HERE' ] || { echo "edit VAULT_TOKEN in this file first"; exit 1; }
H="X-Vault-Token: $VAULT_TOKEN"

echo "== $V"
echo "-- policy ${PROJECT}-ci-ro"
# NOTE: uBixVault takes RAW HCL here, not a {"policy": ...} wrapper (the wrapper
# silently stores empty rules -> 403 on every read).
curl -sS -f -H "$H" -X PUT "$V/v1/sys/policies/acl/${PROJECT}-ci-ro" \
  --data 'path "secret/data/${PROJECT}/*" {
  capabilities = ["read"]
}
path "secret/metadata/${PROJECT}/*" {
  capabilities = ["read", "list"]
}
' && echo "   ok"

# Seed the secrets the pipeline reads. Export the values before running; any
# missing group is skipped and can be written later.
seed() { # seed <name> key=value...
  local name="$1"; shift; local json
  json="$(python3 -c 'import json,sys; print(json.dumps({"data": dict(a.split("=",1) for a in sys.argv[1:])}))' "$@")"
  curl -sS -f -H "$H" -X POST "$V/v1/secret/data/${PROJECT}/$name" -d "$json" >/dev/null && echo "   secret/${PROJECT}/$name ok"
}
[ -n "${TEST_DB_HOST:-}" ] && seed test-db host="$TEST_DB_HOST" port="${TEST_DB_PORT:-3306}" username="$TEST_DB_USERNAME" password="$TEST_DB_PASSWORD" database="$TEST_DB_DATABASE"
[ -n "${COMPOSER_DEPLOY_TOKEN:-}" ] && seed composer username="$COMPOSER_DEPLOY_USERNAME" token="$COMPOSER_DEPLOY_TOKEN"
[ -n "${DISCORD_OPS_WEBHOOK_URL:-}" ] && seed discord ops_webhook_url="$DISCORD_OPS_WEBHOOK_URL" alerts_webhook_url="${DISCORD_ALERTS_WEBHOOK_URL:-}" reviews_webhook_url="${DISCORD_REVIEWS_WEBHOOK_URL:-}"

echo "-- CI token (policy ${PROJECT}-ci-ro, 1 year)"
curl -sS -f -H "$H" -X POST "$V/v1/auth/token/create" \
  -d '{"policies":["${PROJECT}-ci-ro"],"ttl":"8760h"}' \
  | python3 -c 'import json,sys; t=json.load(sys.stdin)["auth"]["client_token"]; print("\n   add as a masked CI/CD variable on this project (Masked, not Protected):\n   '"$VAR"' = " + t + "\n")'

echo "Done."
