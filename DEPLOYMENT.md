# ICTHospital — Deployment Guide

This guide covers the two targets this repository is deployed to:

| Target | URL | Stack |
| --- | --- | --- |
| Local development (Windows / Laragon) | http://127.0.0.1:8000 | PHP 8.3, MySQL 8.4 |
| Hostinger shared hosting | https://greenyellow-zebra-564499.hostingersite.com | PHP 8.3, MariaDB 11.8 |

Source of truth: <https://github.com/AbdurRhman55/ICT-Hospital>

---

## 1. Local (Laragon on Windows)

### One-time setup

```powershell
git clone https://github.com/AbdurRhman55/ICT-Hospital.git D:\ICT-Hospital
cd D:\ICT-Hospital
composer install
Copy-Item .env.example .env
# edit .env: DB_DATABASE=icthospital, DB_USERNAME=root, DB_PASSWORD=
php artisan key:generate
php artisan passport:keys
php artisan migrate --seed
php artisan db:seed --class=DemoDataSeeder   # optional demonstration data
```

Create the database first if it does not exist:

```powershell
C:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysql.exe -uroot -e "CREATE DATABASE icthospital CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

### Run

```powershell
.\deploy\local\start.ps1
```

The application is then on <http://127.0.0.1:8000> (and on the LAN on port 8000).

This machine also starts the server automatically at logon through
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ICTHospital-Local.vbs`.
Remove that file if you would rather start it by hand.

### Optional: a `.test` hostname

Laragon auto-creates a virtual host for any folder in `C:\laragon\www`. To use
`http://icthospital.test`, run Laragon **as administrator**, then:

```powershell
New-Item -ItemType Junction -Path C:\laragon\www\ICTHospital -Target D:\ICT-Hospital
```

Laragon reloads and the hostname is available. This step needs administrator
rights because Laragon edits `C:\Windows\System32\drivers\etc\hosts`.

### Demo accounts

| Login | Password | Role |
| --- | --- | --- |
| `admin` | `123456` | Admin |
| `doctor` | `Demo@2026` | Doctor |
| `nurse` | `Demo@2026` | Nurse |
| `reception` | `Demo@2026` | Reception |
| `accounts` | `Demo@2026` | Accountant |

> Change the admin password before the instance is reachable from the internet.

---

## 2. Hostinger shared hosting

### 2.1 Server facts

| Item | Value |
| --- | --- |
| SSH | `ssh -p 65002 u817261572@185.232.14.194` |
| PHP | 8.3.36 (`/opt/alt/php83/usr/bin/php`) |
| Composer | 2.9.8 |
| Database | MariaDB 11.8 |
| Web server | LiteSpeed |
| Domain | `greenyellow-zebra-564499.hostingersite.com` |
| App directory | `~/domains/<domain>/icthospital` |
| Document root | `~/domains/<domain>/public_html` |

### 2.2 Layout

Laravel is **not** placed inside `public_html`. Only its `public/` directory is,
so `.env`, `vendor/`, `storage/` and the source code are unreachable over HTTP.

```
~/domains/<domain>/
├── icthospital/          # application, outside the web root
│   ├── .env              # secrets, chmod 600
│   ├── storage/          # logs, sessions, uploads
│   └── public/           # source of the public assets
└── public_html/          # document root
    ├── index.php         # boots ../icthospital
    ├── .htaccess
    ├── assets/ css/ js/ img/
    └── storage -> ../icthospital/storage/app/public
```

### 2.3 First deployment

1. Create the database in **hPanel → Databases → MySQL Databases**:
   - database: `u817261572_icthospital`
   - user: `u817261572_icthospital`
   - password: a long random string
2. Create `.env` on the server from `.env.production.example` and set
   `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` and `APP_URL`.
3. Run the deploy script:

```bash
ssh -p 65002 u817261572@185.232.14.194
cd ~/domains/greenyellow-zebra-564499.hostingersite.com
bash icthospital/deploy/hostinger/deploy.sh --seed
```

`--seed` creates the administrator and the permission catalogue.
Use `--demo` instead of `--seed` to also load the demonstration data.

### 2.4 Updating

Push to `main`, then run the same command without flags:

```bash
bash ~/domains/greenyellow-zebra-564499.hostingersite.com/icthospital/deploy/hostinger/deploy.sh
```

The script fetches `origin/main`, installs dependencies, runs pending
migrations, republishes the public assets and rebuilds the caches.

### 2.5 Scheduler

The two reminder jobs are registered in `routes/console.php`. Add one cron entry
in **hPanel → Advanced → Cron Jobs** (every minute):

```
* * * * * cd ~/domains/greenyellow-zebra-564499.hostingersite.com/icthospital && /opt/alt/php83/usr/bin/php -d disable_functions= artisan schedule:run >> /dev/null 2>&1
```

### 2.6 Hostinger-specific notes

Hostinger's PHP selector on this account disables two things the tooling needs.
`deploy/hostinger/deploy.sh` works around both automatically:

| Restriction | Effect | Workaround in the deploy script |
| --- | --- | --- |
| `proc_open` in `disable_functions` | Composer's post-install hook fails | Composer runs with `--no-scripts`; `artisan package:discover` is run directly with `-d disable_functions=` |
| `ext-sodium` not enabled for PHP 8.3 | Composer refuses to install `lcobucci/jwt` | Installs with `--ignore-platform-req=ext-sodium`; Passport signs with RSA/OpenSSL, which works |
| `symlink()` disabled in PHP | `artisan storage:link` fails | The `public_html/storage` link is created with `ln -s` in bash |

To enable sodium for the web SAPI as well, tick **sodium** in
**hPanel → Advanced → PHP Configuration → PHP extensions**.

### 2.6 Backups

```bash
# Database
mysqldump -u u817261572_icthospital -p u817261572_icthospital \
  | gzip > ~/backups/icthospital-$(date +%F-%H%M).sql.gz

# Uploads and environment
tar czf ~/backups/icthospital-files-$(date +%F).tar.gz \
  -C ~/domains/greenyellow-zebra-564499.hostingersite.com \
  icthospital/storage/app icthospital/.env
```

Store backups off the server as well (Hostinger → Files → Backups, or an
external destination).

---

## 3. Security checklist

- [ ] `APP_ENV=production` and `APP_DEBUG=false`
- [ ] `APP_KEY` generated on the server, never reused from another install
- [ ] `.env` is `chmod 600` and never committed
- [ ] Admin password changed from `123456`
- [ ] HTTPS forced (Hostinger issues a free certificate; enable *Force HTTPS*)
- [ ] `SESSION_SECURE_COOKIE=true`
- [ ] Server cron runs `schedule:run`
- [ ] Database backups scheduled and tested

---

## 4. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| 500 on every page | `storage/` or `bootstrap/cache/` not writable, or `.env` missing |
| `SQLSTATE[HY000] [1045]` | Wrong `DB_*` credentials in `.env` |
| `No application encryption key` | `php artisan key:generate --force` |
| `Passport keys not found` | `php artisan passport:keys --force` |
| Blank page, no error | `APP_DEBUG=true` temporarily, then read `storage/logs/laravel.log` |
| Assets 404 | Re-run the deploy script; it republishes `public/` |
| Permission denied on `/dashboard` | `php artisan hospital:sync-permissions` |

---

## 5. Verified baseline

- Local: login as `admin`, dashboard, patients, appointments, billing, reports
- Demo data: 4 departments, 4 doctors, 5 patients, OPD queue for today
- Test suite: `php artisan test`
- Route smoke test: `bash smoke-test.sh`
