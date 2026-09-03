# uBixCore skeleton

The starting point for a project built on [uBixCore](https://gitlab.brainchurts.com/ubixsys/ubixcore):
thin entry points, one example app, the quality gate wired to the rules that ship
in the framework, and nothing from the framework committed in your repo.

```bash
composer create-project ubixsys/ubixcore-skeleton acme
cd acme
php bin/ubix list                       # the uBixCore CLI, plus any App\Console\Command\* you add
APP_NAME=HelloApi php -S 127.0.0.1:8080 -t public
curl 127.0.0.1:8080/health              # {"status":"ok","app":"HelloApi"}
php bin/ubix code:review                # phpcs + phpstan (level max) + phpunit
```

## Layout

```
composer.json / composer.lock   requires ubixsys/ubixcore - commit the lock, it pins the framework your images are built from
bin/ubix                        CLI entry point (yours; lists the command namespaces to scan)
public/index.php                web entry point (yours; serves app/<APP_NAME>)
app/HelloApi/src/               Dependencies.php (PHP-DI), Middleware.php, Routes.php - one folder per deployable app
app/UbixCli/src/                the CLI's container definitions
php/App/                        your code, PSR-4 root App\  (rename: composer.json autoload + the namespace)
tests/                          App\Tests\ - every concrete class needs a test case (tests/PhpunitTestCasesTest.php enforces it)
templates/default/              Latte templates
sql/migrations/                 bin/ubix migrate:*
phpcs.xml phpstan.neon phpunit.xml   point at the rules in vendor/ubixsys/ubixcore
Dockerfile                      one runtime image per app: docker build --build-arg APP_NAME=HelloApi .
.env.example                    copied to .env on create-project; never commit .env
```

`Ubix\` is the framework's namespace: never put code there. Your namespace is
whatever `composer.json` maps (`App\` by default); the framework finds your
commands, apps and tests through that map.

## Secrets: use uBixVault

uBixCore is built to take its credentials from **[uBixVault](https://ubixsys.com)**,
the uBix family's secrets manager, not from files in the repo. The framework's
bootstrap resolves database credentials from Vault on every start when
`VAULT_ADDR` is set and exports them to the environment before the SQL layer
reads them; the `.env` file is a local-development fallback only and is never
committed.

```
VAULT_ADDR=https://vault.example.com     # turns the hook on
VAULT_TOKEN=...                          # local dev / CI - or, in Kubernetes:
VAULT_K8S_ROLE=acme-api                  # service-account auth, no token on disk
VAULT_DB_KV_PATH=app/db                  # KV v2 secret holding read_/write_username + _password
```

The secret's keys `read_username`, `read_password`, `write_username`,
`write_password` become `MYSQL_READ_*` / `MYSQL_WRITE_*`. CI tokens, webhooks
and API keys follow the same pattern: store them in Vault, read them in the
pipeline with a read-only token, and keep `.env` empty of anything you would
not paste into a chat.

## Adding things

- **An endpoint:** a controller under `php/App/Controller/` extending
  `Ubix\Controller\AbstractController` (alias it `Controller`), one line in
  `app/<App>/src/Routes.php`, a test under `tests/Controller/`.
- **A CLI command:** `php/App/Console/Command/<Name>Command.php` extending
  `Ubix\Console\Command\AbstractCommand`; `bin/ubix` already scans
  `App\Console\Command`.
- **A second app:** copy `app/HelloApi` and deploy it with its own `APP_NAME`.
- **Upgrading uBixCore:** `composer update ubixsys/ubixcore`, commit the lock.

## Developing against a local uBixCore checkout

While hacking on the framework and your project together, point Composer at
the checkout instead of GitLab (symlinked, so edits are live):

```bash
composer config repositories.ubixcore path ../ubixcore
composer require "ubixsys/ubixcore:*@dev"
```

Do not commit that `repositories` entry; drop it (and re-require the released
constraint) before pushing.
