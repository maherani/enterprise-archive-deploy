# راهنمای جامع استقرار و راهبری سامانه آرشیو اسناد سازمانی (Runbook v2.0)

> **نسخه سند:** v2.0 (ویرایش معماری زیرماژول‌ها و Named Volumes)  
> **شاخه هدف:** `release/v2-staging-verified`  
> **مخزن ارکستراتور:** `enterprise-archive-deploy`  
> **مخاطب:** تیم‌های DevOps، مدیران سیستم و مهندسان استقرار (Staging & Production)

---

## ۱. معماری سه‌لایه و مدیریت ولوم‌های پایدار (Updated Architecture with Named Volumes)

در نسخه v2.0، جهت جلوگیری از **Shadow شدن فایل‌های هسته Nextcloud** (ناشی از بایند مانت پوشه خالی هاست روی `/var/www/html`) و همچنین رفع کامل **خطای دسترسی SQLite (`SQLITE_CANTOPEN` / Permission Denied)** در کانتینر AnythingLLM، معماری ذخیره‌سازی به ترکیبی از **Named Volumes مدیریت‌شده توسط داکر** و **Bind Mountهای ایزوله** ارتقا یافته است:

```text
                        ┌──────────────────────────────────────────────┐
                        │     مخزن کلان: enterprise-archive-deploy     │
                        └──────────────────────┬───────────────────────┘
                                               │
        ┌──────────────────────────────────────┼──────────────────────────────────────┐
        ▼                                      ▼                                      ▼
┌───────────────────────────┐      ┌───────────────────────────┐      ┌───────────────────────────┐
│   لایه ۱: هسته آرشیو       │      │  لایه ۲: گیتوی و هسته AI   │      │  لایه ۳: یکپارچه‌سازی      │
│      (archive_core)       │      │     (ai_box_gateway)      │      │   (integration_layer)     │
├───────────────────────────┤      ├───────────────────────────┤      ├───────────────────────────┤
│ • archive_proxy (Nginx)   │      │ • ai_box_gateway (:3001)  │      │ • AMQP Outbox Publisher   │
│ • archive_app (Nextcloud) │◄────►│ • ai_box_anythingllm      │◄────►│ • Secure File Stream Proxy│
│ • archive_db (Postgres 15)│      │ • ai_box_ollama           │      │ • RabbitMQ Event Consumer │
│                           │      │ • ai_box_rabbitmq (:5672) │      │                           │
└─────────────┬─────────────┘      └─────────────┬─────────────┘      └───────────────────────────┘
              │                                  │
              ▼                                  ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              لایه ذخیره‌سازی پایدار (Storage Layer)                              │
├─────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. Docker Named Volumes (مدیریت خودکار سورس و دیتابیس بدون تداخل با فایل‌سیستم هاست):             │
│    • nextcloud_html   ──► /var/www/html (تزریق خودکار هسته Nextcloud توسط entrypoint رسمی)       │
│    • archive_db_data  ──► /var/lib/postgresql/data (پایداری ۱۴۵ جدول دیتابیس PostgreSQL)        │
│    • ollama_models    ──► /root/.ollama (نگهداری وزن مدل‌های زبانی و Embedding)                  │
│                                                                                                 │
│ 2. Selective Bind Mounts (فقط برای کدهای سفارشی و داده‌های مشترک با UID/GID تنظیم‌شده):          │
│    • ./archive_core/apps/archive_autotag ──► /var/www/html/custom_apps/archive_autotag:ro       │
│    • ./ai_box_gateway/data/anythingllm   ──► /app/server/storage (با مالکیت الزامی 1000:1000)   │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### مزایای کلیدی معماری ولوم‌های v2.0:
1. **حذف خطای Shadowing در Nextcloud:** با استفاده از Named Volume به نام `nextcloud_html`، ایمیج رسمی `nextcloud:apache` در اولین راه‌اندازی به طور خودکار تمامی فایل‌های هسته را درون ولوم کپی کرده و اپ سفارشی `archive_autotag` به صورت Read-Only در مسیر `custom_apps/archive_autotag` مانت می‌شود.
2. **تضمین دسترسی SQLite در AnythingLLM:** کانتینر AnythingLLM با کاربر داخلی `uid=1000(anythingllm)` اجرا می‌شود. پیش از بالا آمدن کانتینرها، مسیر `./ai_box_gateway/data/anythingllm` ساخته شده و مالکیت `1000:1000` با سطح دسترسی `775` روی آن اعمال می‌گردد.

---

## ۲. جدول متغیرهای محیطی الزامی (`.env`)

پیش از اجرای استقرار، فایل `.env` در ریشه مخزن `enterprise-archive-deploy` باید بر اساس جدول زیر پیکربندی شود:

| نام متغیر | مقدار پیش‌فرض / نمونه | سرویس مصرف‌کننده | شرح کاربرد |
| :--- | :--- | :--- | :--- |
| `POSTGRES_DB` | `nextcloud` | `db`, `app` | نام پایگاه داده اصلی در PostgreSQL |
| `POSTGRES_USER` | `nextcloud_user` | `db`, `app` | نام کاربری پایگاه داده |
| `POSTGRES_PASSWORD` | `StrongDBPass123!` | `db`, `app` | رمز عبور پایگاه داده (الزامی) |
| `NEXTCLOUD_ADMIN_USER` | `admin` | `app` | نام کاربری مدیر ارشد سامانه در نصب اولیه |
| `NEXTCLOUD_ADMIN_PASSWORD` | `StrongAdminPass123!` | `app` | رمز عبور مدیر ارشد سامانه (الزامی) |
| `NEXTCLOUD_TRUSTED_DOMAINS` | `"localhost 127.0.0.1 docs.maskan"` | `app` | لیست دامنه‌ها و IPهای مجاز دسترسی به پورتال |
| `GATEWAY_PORT` | `3001` | `gateway` | پورت محلی درگاه امنیتی هوش مصنوعی |
| `BACKEND_HOST` | `anythingllm` | `gateway` | آدرس سرویس داخلی موتور RAG |
| `BACKEND_PORT` | `3001` | `gateway` | پورت داخلی سرویس AnythingLLM |
| `INTERNAL_SERVICE_KEY` | `ai_box_internal_api_secret_key` | `gateway` | کلید مشترک احراز هویت داخلی سرویس‌ها |
| `DESTINATION_API_KEY` | `ai_box_internal_api_secret_key` | `gateway` | کلید API ارتباط با مقصد پردازش هوش مصنوعی |
| `SESSION_ACL_CACHE_TTL` | `3600` | `gateway` | زمان اعتبار کش نشست‌های کاربری (بر حسب ثانیه) |
| `VECTOR_DB` | `lancedb` | `anythingllm` | موتور پایگاه داده برداری داخلی |
| `EMBEDDING_MODEL_PREF` | `qwen2.5:0.5b-instruct` | `anythingllm` | مدل پیش‌فرض استنتاج و برداری‌سازی در Ollama |
| `RABBITMQ_DEFAULT_USER` | `guest` | `rabbitmq` | نام کاربری کارگزار پیام RabbitMQ |
| `RABBITMQ_DEFAULT_PASS` | `guest` | `rabbitmq` | رمز عبور کارگزار پیام RabbitMQ |
| `RABBITMQ_PORT` | `5672` | `rabbitmq` | پورت پروتکل AMQP روی هاست |

---

## ۳. اسکریپت خودکار استقرار یکپارچه (`deploy.sh`)

برای استقرار بدون خطا در سرور جدید (Staging یا Production)، اسکریپت `deploy.sh` زیر را در ریشه مخزن `enterprise-archive-deploy` ایجاد و اجرا نمایید. این اسکریپت تمامی پیش‌نیازهای دایرکتوری، مجوزهای `1000:1000` برای SQLite در AnythingLLM، راه‌اندازی کانتینرها و فعال‌سازی ماژول `archive_autotag` را به صورت خودکار انجام می‌دهد:

```bash
cat << 'EOF' > deploy.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=================================================================="
echo " Enterprise Archive System - Unified Deployment Script (v2.0)"
echo "=================================================================="

# ۱. بررسی و همگام‌سازی زیرماژول‌های گیت
echo "[1/6] Syncing Git submodules on branch release/v2-staging-verified..."
git submodule update --init --recursive

# ۲. بررسی وجود فایل .env
if [ ! -f .env ]; then
    echo "[2/6] Creating .env from .env.example..."
    cp .env.example .env
else
    echo "[2/6] Using existing .env file."
fi

# ۳. ایجاد دایرکتوری‌های داده و تنظیم مجوزهای AnythingLLM (رفع خطای SQLite)
echo "[3/6] Preparing AI Box storage directories and permissions (UID 1000:1000)..."
mkdir -p ./ai_box_gateway/data/anythingllm
mkdir -p ./ai_box_gateway/data/rabbitmq

if [ -f ./archive_core/data/gid_workspace_map.json ] && [ ! -f ./ai_box_gateway/data/gid_workspace_map.json ]; then
    cp ./archive_core/data/gid_workspace_map.json ./ai_box_gateway/data/gid_workspace_map.json
elif [ ! -f ./ai_box_gateway/data/gid_workspace_map.json ]; then
    echo "{}" > ./ai_box_gateway/data/gid_workspace_map.json
fi

sudo chown -R 1000:1000 ./ai_box_gateway/data/anythingllm
sudo chmod -R 775 ./ai_box_gateway/data/anythingllm
sudo chmod 664 ./ai_box_gateway/data/gid_workspace_map.json || true

# ۴. راه‌اندازی و ساخت سرویس‌های ۷گانه داکر
echo "[4/6] Launching 7 Docker containers with Named Volumes..."
docker compose up -d --build

# ۵. انتظار برای تکمیل نصب اولیه Nextcloud در Named Volume
echo "[5/6] Waiting for Nextcloud core initialization inside nextcloud_html volume..."
MAX_RETRIES=30
COUNT=0
until docker exec -u www-data archive_app php occ status 2>/dev/null | grep -q "installed: true"; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
        echo "ERROR: Nextcloud initialization timed out after $MAX_RETRIES attempts."
        exit 1
    fi
    echo "  -> Waiting for Nextcloud installation to finish... ($COUNT/$MAX_RETRIES)"
    sleep 5
done

# ۶. فعال‌سازی ماژول سفارشی archive_autotag و ایجاد پوشه ریشه سازمانی
echo "[6/6] Enabling archive_autotag app and initializing Enterprise_Archive root..."
docker exec -u www-data archive_app php occ app:enable archive_autotag
docker exec -u www-data archive_app bash -c "
    mkdir -p /var/www/html/data/admin/files/Enterprise_Archive &&
    chown -R www-data:www-data /var/www/html/data/admin/files/Enterprise_Archive &&
    chmod 0770 /var/www/html/data/admin/files/Enterprise_Archive
"
docker exec -u www-data archive_app php occ files:scan --all

echo "=================================================================="
echo " Deployment Completed Successfully!"
echo "=================================================================="
EOF

chmod +x deploy.sh
./deploy.sh
```

---

## ۴. سناریوهای ۴گانه اعتبارسنجی عملیاتی (Operational Verification Scenarios)

پس از اتمام اجرای `deploy.sh`، هر ۴ سناریوی زیر باید اجرا شده و خروجی مورد انتظار تایید گردد:

### سناریوی ۱: بررسی سلامت کانتینرها و شبکه (Health Check)
```bash
docker compose ps
```
- **معیار پذیرش:** هر ۷ کانتینر (`archive_db`, `archive_app`, `archive_proxy`, `ai_box_ollama`, `ai_box_anythingllm`, `ai_box_gateway`, `ai_box_rabbitmq`) باید در وضعیت `Up` باشند و کانتینرهای دارای Healthcheck (`archive_db`, `ai_box_rabbitmq`, `ai_box_anythingllm`) وضعیت `(healthy)` را نشان دهند.

### سناریوی ۲: بررسی وضعیت دیتابیس و هسته Nextcloud (DB & Core Check)
```bash
# بررسی وضعیت نصب Nextcloud
docker exec -u www-data archive_app php occ status

# بررسی تعداد جداول ایجادشده در PostgreSQL
docker exec archive_db psql -U nextcloud_user -d nextcloud -t -A -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
```
- **معیار پذیرش:** خروجی `occ status` باید `installed: true` و `maintenance: false` باشد و پایگاه داده شامل جداول کامل هسته و ماژول آرشیو (از جمله `oc_archive_tag_ownership` و `oc_archive_ai_outbox`) باشد.

### سناریوی ۳: بررسی سلامت AnythingLLM و دیتابیس SQLite (AnythingLLM Status)
```bash
# بررسی عدم وجود خطای مجوز SQLite در لاگ‌های AnythingLLM
docker logs --tail 50 ai_box_anythingllm

# بررسی ایجاد فایل دیتابیس SQLite در مسیر استوریج
ls -lh ./ai_box_gateway/data/anythingllm/anythingllm.db

# تست پاسخ‌دهی گیتوی هوش مصنوعی
curl -i http://127.0.0.1:3001/api/v1/workspaces
```
- **معیار پذیرش:** فایل `anythingllm.db` با مالکیت `1000:1000` ایجاد شده باشد، هیچ خطای `Unable to open the database file` در لاگ‌ها نباشد و پورت `3001` گیتوی پاسخ HTTP برگرداند (کد `401`/`403` برای درخواست بدون کوکی سشن که نشان‌دهنده فعال بودن لایه امنیتی گیتوی است).

### سناریوی ۴: بررسی خودترمیم گروه دسترسی هوش مصنوعی و ماژول تگ‌گذاری (Auto-tag & Self-Healing Group)
```bash
# بررسی فعال بودن اپ archive_autotag
docker exec -u www-data archive_app php occ app:list | grep archive_autotag

# بررسی ایجاد خودکار گروه ai_chat_access توسط Application::boot()
docker exec -u www-data archive_app php occ group:list | grep ai_chat_access
```
- **معیار پذیرش:** اپلیکیشن `archive_autotag` در لیست `Enabled` قرار داشته باشد و گروه `ai_chat_access` به صورت خودکار در لیست گروه‌های سیستم ثبت شده باشد.

---

## ۵. دستورالعمل ریست کامل و پاکسازی محیط تستی (Clean State Reset)

در صورتی که در محیط آزمایشگاهی (Staging) نیاز به پاکسازی کامل تمامی داده‌ها، ولوم‌های داکر (`nextcloud_html`, `archive_db_data`, `ollama_models`) و بازگشت به نقطه صفر پیش از استقرار مجدد باشد، دستورات زیر را به ترتیب اجرا کنید:

```bash
# ۱. توقف کانتینرها و حذف کامل Named Volumes و شبکه‌ها
docker compose down -v --remove-orphans

# ۲. پاکسازی داده‌های زمان اجرای AnythingLLM و RabbitMQ روی هاست
sudo rm -rf ./ai_box_gateway/data/anythingllm/*
sudo rm -rf ./ai_box_gateway/data/rabbitmq/*
sudo rm -f ./ai_box_gateway/data/*.db ./ai_box_gateway/data/*.db-shm ./ai_box_gateway/data/*.db-wal

# ۳. بازسازی مجدد ساختار تمیز و اجرای استقرار از صفر
./deploy.sh
```

> [!WARNING]
> اجرای `docker compose down -v` تمامی ولوم‌های پایدار شامل دیتابیس PostgreSQL و فایل‌های آپلودشده در Nextcloud را به طور کامل حذف می‌کند. استفاده از این دستور صرفاً در سرور آزمایشگاهی (Staging) مجاز بوده و در محیط عملیاتی (Production) اکیداً ممنوع است.
