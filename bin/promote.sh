#!/usr/bin/bash
# promote.sh <staging|main> — auto-promote the current pipeline commit to the
# next branch (dev→staging, staging→main)
# is auto until the platform is live — see docs/projects/ci-parity CP-09).
#
# Runs after a green deploy of the source branch. Safety properties:
#   - Destructive-migration halt: a `Destructive:` marker in the migrations
#     being promoted halts the auto flow (exit 0, Discord warning); a human
#     presses the *-destructive manual job, which re-runs this script with
#     PROMOTE_ACK_DESTRUCTIVE=1.
#   - Backwards guard: if the target already contains the commit, no-op.
#   - Fast-forward only. Never forces. A non-ff means the target was written
#     directly — reconcile by hand.
# Needs GITLAB_PROMOTE_TOKEN (project access token, Maintainer, write_repository,
# allowed to push to protected staging/main).
set -u
TARGET="${1:?staging|main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$SCRIPT_DIR/bin/lib/notify.sh"
SHA="${CI_COMMIT_SHA:-$(git -C "$SCRIPT_DIR" rev-parse HEAD)}"
SHORT="${CI_COMMIT_SHORT_SHA:-${SHA:0:8}}"
SRC="${CI_COMMIT_REF_NAME:-$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)}"
WHO="${GITLAB_USER_LOGIN:-${GITLAB_USER_NAME:-unknown}}"
LINK="${CI_PIPELINE_URL:-}"

git -C "$SCRIPT_DIR" fetch -q origin "$TARGET" 2>/dev/null || true
TARGET_SHA=$(git -C "$SCRIPT_DIR" rev-parse FETCH_HEAD 2>/dev/null || echo '')

# destructive-migration carve-out (docs/standards/migrations.md)
DESTRUCTIVE=$(git -C "$SCRIPT_DIR" diff "${TARGET_SHA:-origin/$TARGET}..$SHA" -- 'sql/migrations/*.sql' 2>/dev/null | grep '^[+].*Destructive:' || true)
if [ -n "$DESTRUCTIVE" ]; then
    if [ "${PROMOTE_ACK_DESTRUCTIVE:-0}" = "1" ]; then
        echo "Destructive migration in batch — ACKNOWLEDGED by $WHO. Proceeding."
        discord ops 15105570 "⚠️ ${SRC}→${TARGET}: promoting WITH a destructive migration" "\`${SHORT}\` acknowledged by ${WHO}${LINK:+\nPipeline: ${LINK}}"
    else
        echo "${SRC}->${TARGET} auto-promotion HALTED: destructive migration in the batch. Review, then run the promote-to-${TARGET}-destructive manual job."
        discord alerts 15105570 "⚠️ ${SRC}→${TARGET} promotion halted" "A \`Destructive:\` migration is in \`${SHORT}\`. Review it, then run **promote-to-${TARGET}-destructive** on the pipeline.${LINK:+\nPipeline: ${LINK}}"
        exit 0
    fi
fi

if [ -n "$TARGET_SHA" ] && git -C "$SCRIPT_DIR" merge-base --is-ancestor "$SHA" "$TARGET_SHA" 2>/dev/null; then
    echo "$TARGET already contains $SHORT — nothing to promote."; exit 0
fi

TOKEN="${GITLAB_PROMOTE_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    echo "GITLAB_PROMOTE_TOKEN not set — cannot promote."
    discord alerts 15158332 "❌ ${SRC}→${TARGET} promotion failed" "GITLAB_PROMOTE_TOKEN is not configured (\`${SHORT}\`)."
    exit 1
fi
URL="https://oauth2:${TOKEN}@${CI_SERVER_HOST:-gitlab.brainchurts.com}/${CI_PROJECT_PATH:?CI_PROJECT_PATH}.git"
echo "Promoting ${SRC}@${SHORT} -> ${TARGET} (fast-forward only)…"
if OUT=$(git -C "$SCRIPT_DIR" push "$URL" "${SHA}:refs/heads/${TARGET}" 2>&1); then
    echo "$OUT"; echo "Promoted to $TARGET."
    discord ops 3066993 "🚀 Promoted ${SRC} → ${TARGET}" "\`${SHORT}\` ${CI_COMMIT_TITLE:-} — the ${TARGET} pipeline now builds + deploys.${LINK:+\nPipeline: ${LINK}}"
else
    echo "$OUT"
    case "$OUT" in
        *"401"*|*"Authentication failed"*|*"Access denied"*) reason="token auth failed — refresh GITLAB_PROMOTE_TOKEN" ;;
        *"protected branch"*|*"pre-receive hook declined"*)  reason="branch protection — allow Maintainers to push to ${TARGET}" ;;
        *"non-fast-forward"*|*"[rejected]"*|*"fetch first"*)  reason="${TARGET} diverged from the promotion flow — reconcile manually (never forced)" ;;
        *) reason="see job log" ;;
    esac
    echo "push to $TARGET FAILED: $reason"
    discord alerts 15158332 "❌ ${SRC}→${TARGET} promotion failed" "${reason} (\`${SHORT}\`)${LINK:+\nPipeline: ${LINK}}"
    exit 1
fi
