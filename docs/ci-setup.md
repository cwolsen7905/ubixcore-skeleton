# CI setup for a uBixCore host project

Everything the pipeline in `.gitlab-ci.yml` needs before it goes green, in the
order to create it. Secrets live in **uBixVault**; GitLab holds only the
read-only tokens that let jobs fetch them. Nothing here is committed.

Stages: `build` (runtime image + test image + optional node image) →
`lint-and-test` (phpcs, phpstan, phpunit, js-lint) → `deploy` (`bin/deploy.sh
<env>` applies `app/*/<env>-{deploy,ingress,service}.yaml`) → `promote`
(`bin/promote.sh` fast-forwards dev → staging → main) → `notify` (Discord).

## 1. A runner

Any GitLab runner with the tag `shell`, Docker with a buildx builder named
`multiarch-builder`, and kubeconfigs for your clusters at the paths
`bin/deploy.sh` expects (`/home/gitlab-runner/.kube/devstageconfig`, …). An
instance-wide shared runner serves every project with no per-project setup.

## 2. Access to uBixCore (the private Composer registry)

The runtime image runs `composer install`, which fetches `ubixsys/ubixcore` from
the `ubixsys` group Composer registry. Two options; the build job tries the
first and falls back to the second:

- **Deploy token in Vault (recommended):** on the `ubixsys` group create a
  deploy token with `read_package_registry`; store it as
  `secret/<project>/composer` with keys `username` and `token` (step 4 does this).
- **Job token allowlist:** on the `ubixsys/ubixcore` project, Settings → CI/CD
  → Job token permissions, add your project (only needed while the packages
  come from a private GitLab registry).
- **Base image:** the Dockerfiles default to the public
  `ghcr.io/ubixsys/ubixcore-php:8.5`; nothing to configure. To build from a
  private mirror instead, pass `--build-arg BASE_IMAGE=<registry>/<image>:<tag>`
  in the build job.

Developers also need the token locally, once:
`composer config -g gitlab-token.<gitlab host> <username> <token>`.

## 3. GitLab CI/CD variables (Settings → CI/CD → Variables, all Masked, not Protected)

| Variable | What | Where it comes from |
|---|---|---|
| `UBIXVAULT_CI_TOKEN_DEV` | read-only Vault token for the dev branch | printed by `bin/vault-ci-setup.sh dev <project>` |
| `UBIXVAULT_CI_TOKEN_PROD` | same for staging/main | `bin/vault-ci-setup.sh prod <project>` |
| `GITLAB_PROMOTE_TOKEN` | lets `bin/promote.sh` push staging/main | project access token on **this** project: Maintainer, scopes `api` + `write_repository` |

`CI_REGISTRY_*` and `CI_JOB_TOKEN` are provided by GitLab.

## 4. uBixVault secrets (`secret/<project>/…`)

Run once per Vault with an admin token in the environment (never in a file):

```bash
export VAULT_TOKEN=<admin> VAULT_ADDR=https://vault.dev.example.com
export TEST_DB_HOST=… TEST_DB_PORT=3306 TEST_DB_USERNAME=… TEST_DB_PASSWORD=… TEST_DB_DATABASE=…
export COMPOSER_DEPLOY_USERNAME=… COMPOSER_DEPLOY_TOKEN=…
export DISCORD_OPS_WEBHOOK_URL=… DISCORD_ALERTS_WEBHOOK_URL=…
./bin/vault-ci-setup.sh dev <project>
```

It creates the policy `<project>-ci-ro` (read on `secret/<project>/*`), writes
`test-db`, `composer`, `discord`, and prints the CI token for step 3.

| Secret | Keys | Read by |
|---|---|---|
| `secret/<project>/test-db` | host, port, username, password, database | phpunit job (`database:resetSchema test`, `migrate:up`) |
| `secret/<project>/composer` | username, token | build job (Composer auth as a BuildKit secret) |
| `secret/<project>/discord` | ops_webhook_url, alerts_webhook_url, reviews_webhook_url | `bin/lib/notify.sh` |
| `secret/<project>/db-<tier>` (`dev`, `staging`, `prod`) | host, port, database, write_username, write_password; optional migration_username, migration_password (a dedicated DDL user, recommended) | migrate jobs (`migrate:status` + `migrate:up --target=<tier>` before each deploy) |
| `secret/<app>/<env>/db` | read_username, read_password, write_username, write_password | the running pods (`VAULT_ADDR` + `VAULT_K8S_ROLE`, see the app manifests) |

## 5. Kubernetes

- Image pull secret `regcred` in every target namespace (a deploy token with
  `read_registry`).
- A uBixVault Kubernetes-auth role bound to the namespace and ServiceAccount
  your pods use, named in `VAULT_K8S_ROLE` in `app/*/<env>-deploy.yaml`.
- Non-secret runtime config (`MEMCACHE_SERVERS`, `MYSQL_*_HOST/PORT/DATABASE`,
  `LOGGER_PATH`, `LATTE_*`, `LOG_LEVEL`, `IS_*`) as `env` on the Deployment.
  **Do not bake a `.env` into the image** — the image ships none on purpose.

## 6. First pipeline

Push to `dev`. Expected first-run failures, in order, if a step above was
skipped: Composer 401 (step 2), "no test-db credentials from vault" (steps 3–4),
deploy `kubectl` errors (step 1 kubeconfig, step 5 secrets).
