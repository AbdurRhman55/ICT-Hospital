#!/usr/bin/env bash
#
# ICTHospital — Hostinger (shared hosting) deployment
# ---------------------------------------------------
# Idempotent: safe to run on first install and on every update.
#
# Layout produced:
#
#   ~/domains/<domain>/
#   ├── icthospital/        Laravel application (outside the web root)
#   │   ├── .env            created from .env.production.example once
#   │   ├── storage/        logs, sessions, uploads
#   │   └── public/         source of the public assets
#   └── public_html/        document root (index.php + assets)
#
# Usage:
#   bash deploy.sh                 # deploy / update
#   bash deploy.sh --seed          # deploy and run the first-install seeders
#   bash deploy.sh --demo          # deploy and load demonstration data
#
# Everything can be overridden with environment variables, e.g.
#   DOMAIN=hospital.example.com bash deploy.sh
#
set -euo pipefail

DOMAIN="${DOMAIN:-greenyellow-zebra-564499.hostingersite.com}"
BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-https://github.com/AbdurRhman55/ICT-Hospital.git}"

DOMAIN_DIR="${DOMAIN_DIR:-$HOME/domains/$DOMAIN}"
APP_DIR="${APP_DIR:-$DOMAIN_DIR/icthospital}"
PUBLIC_HTML="${PUBLIC_HTML:-$DOMAIN_DIR/public_html}"

PHP_BIN="${PHP_BIN:-php}"
COMPOSER_BIN="${COMPOSER_BIN:-composer}"

SEED=0
DEMO=0
for arg in "$@"; do
  case "$arg" in
    --seed) SEED=1 ;;
    --demo) SEED=1; DEMO=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warning] %s\033[0m\n' "$*"; }

# Hostinger's PHP selector disables proc_open and does not load sodium by
# default. Both are needed by Composer and Passport, so provide an override
# for the command line. The web SAPI is unaffected by these flags.
PHP_FLAGS=()
if ! "$PHP_BIN" -m | grep -qi '^sodium$'; then
  PHP_FLAGS+=("-d" "extension=sodium.so")
fi
if ! "$PHP_BIN" -r 'exit(function_exists("proc_open") ? 0 : 1);' >/dev/null 2>&1; then
  PHP_FLAGS+=("-d" "disable_functions=")
fi

php_run() { "$PHP_BIN" "${PHP_FLAGS[@]}" "$@"; }

say "Checking environment"
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v "$PHP_BIN" >/dev/null || { echo "php is required" >&2; exit 1; }
php_run -r 'exit(version_compare(PHP_VERSION, "8.2.0", ">=") ? 0 : 1);' \
  || { echo "PHP 8.2 or newer is required" >&2; exit 1; }

say "Fetching the application into $APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  mkdir -p "$DOMAIN_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
else
  git -C "$APP_DIR" fetch --prune origin "$BRANCH"
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
  git -C "$APP_DIR" clean -fd
fi

cd "$APP_DIR"

say "Installing PHP dependencies"
# --no-scripts: proc_open is disabled on this host; the package manifest is
# rebuilt explicitly below instead of through Composer's post-autoload hook.
"$PHP_BIN" "${PHP_FLAGS[@]}" "$(command -v "$COMPOSER_BIN")" install \
  --no-dev --no-interaction --prefer-dist --optimize-autoloader \
  --no-scripts --ignore-platform-req=ext-sodium

php_run artisan package:discover --ansi >/dev/null

say "Preparing writable directories"
mkdir -p storage/app/public \
         storage/framework/cache/data \
         storage/framework/sessions \
         storage/framework/views \
         storage/logs \
         bootstrap/cache
chmod -R u+rwX storage bootstrap/cache

say "Ensuring the environment file"
if [ ! -f .env ]; then
  cp .env.production.example .env
  warn ".env created from .env.production.example — set the database credentials."
fi
chmod 600 .env

if ! grep -qE '^APP_KEY=base64:.+' .env; then
  php_run artisan key:generate --force
fi

if [ ! -f storage/oauth-private.key ] || [ ! -f storage/oauth-public.key ]; then
  php_run artisan passport:keys --force
fi
chmod 600 storage/oauth-private.key storage/oauth-public.key

say "Running database migrations"
if php_run artisan migrate --force --no-interaction; then
  if [ "$SEED" = "1" ]; then
    php_run artisan db:seed --force --no-interaction
    if [ "$DEMO" = "1" ]; then
      php_run artisan db:seed --class=DemoDataSeeder --force --no-interaction
    fi
  fi
else
  warn "Migrations failed — check DB_* in $APP_DIR/.env. The code is deployed; the site returns 500 until the database is reachable."
fi

say "Publishing the public directory"
mkdir -p "$PUBLIC_HTML"
rsync -a --delete \
  --exclude '.well-known' \
  --exclude 'index.php' \
  --exclude 'storage' \
  "$APP_DIR/public/" "$PUBLIC_HTML/"

cat > "$PUBLIC_HTML/index.php" <<'PHP'
<?php

use Illuminate\Foundation\Application;
use Illuminate\Http\Request;

define('LARAVEL_START', microtime(true));

// The application lives beside public_html, outside the web root.
$appPath = dirname(__DIR__).'/icthospital';

if (file_exists($maintenance = $appPath.'/storage/framework/maintenance.php')) {
    require $maintenance;
}

require $appPath.'/vendor/autoload.php';

/** @var Application $app */
$app = require_once $appPath.'/bootstrap/app.php';

$app->handleRequest(Request::capture());
PHP

# PHP's symlink() is disabled on this host, so the link is made here.
rm -rf "$PUBLIC_HTML/storage"
ln -sfn "$APP_DIR/storage/app/public" "$PUBLIC_HTML/storage"

say "Caching configuration, routes and views"
php_run artisan optimize:clear >/dev/null 2>&1 || true
php_run artisan config:cache
php_run artisan route:cache
php_run artisan view:cache

say "Deployment finished"
echo "Application  : $APP_DIR"
echo "Document root: $PUBLIC_HTML"
echo "URL          : https://$DOMAIN"
