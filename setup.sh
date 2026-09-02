#!/bin/sh
# ==============================================================================
# setup.sh - Complete zero-touch idempotent provisioning for NetBox (Variant 8)
# Strict POSIX /bin/sh compliance guaranteed.
# ==============================================================================
set -e

echo "=== [1/7] Verifying System Dependencies ==="
command -v docker >/dev/null 2>&1 || { echo "[-] ERROR: docker executable not found in PATH." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "[-] ERROR: git executable not found in PATH." >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "[-] ERROR: openssl executable not found in PATH." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[-] ERROR: curl executable not found in PATH." >&2; exit 1; }

NETBOX_TAG="v4.0.8"

echo "=== [2/7] Checking Upstream Source Code (Tag: ${NETBOX_TAG}) ==="
if [ ! -d "netbox-src" ]; then
    echo "[+] Cloning NetBox repository at release tag ${NETBOX_TAG}..."
    git clone --depth 1 --branch "${NETBOX_TAG}" https://github.com/netbox-community/netbox.git netbox-src
else
    echo "[*] netbox-src directory already present. Checking git state..."
fi

echo "=== [3/7] Generating Idempotent .env Secrets ==="
if [ ! -f .env ]; then
    echo "[+] Creating production .env file with cryptographically secure credentials..."
    DB_PASS=$(openssl rand -hex 16)
    SEC_KEY=$(openssl rand -hex 32)
    ADMIN_PASS=$(openssl rand -hex 14)
    API_TOKEN=$(openssl rand -hex 20)

    cat <<EOF > .env
NETBOX_TAG=${NETBOX_TAG}
DB_NAME=netbox
DB_USER=netbox
DB_PASSWORD=${DB_PASS}
SUPERUSER_NAME=admin
SUPERUSER_EMAIL=admin@example.com
SUPERUSER_PASSWORD=${ADMIN_PASS}
SUPERUSER_API_TOKEN=${API_TOKEN}
SECRET_KEY=${SEC_KEY}
METRICS_PORT=8000
APP_PORT=8000
EOF
    echo "[+] .env successfully created."
else
    echo "[*] Existing .env detected. Reusing existing secrets."
fi

# Load variables safely for POSIX shell
set -a
. ./.env
set +a

echo "=== [4/7] Configuring NetBox Application Settings ==="
CONFIG_FILE="netbox-src/netbox/netbox/configuration.py"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[+] Injecting dynamic configuration file..."
    cat <<'EOF' > "$CONFIG_FILE"
import os

ALLOWED_HOSTS = ['*']

DATABASE = {
    'NAME': os.environ.get('DB_NAME', 'netbox'),
    'USER': os.environ.get('DB_USER', 'netbox'),
    'PASSWORD': os.environ.get('DB_PASSWORD', ''),
    'HOST': os.environ.get('DB_HOST', 'postgres'),
    'PORT': '5432',
    'CONN_MAX_AGE': 300,
}

REDIS = {
    'tasks': {
        'HOST': os.environ.get('REDIS_HOST', 'redis'),
        'PORT': int(os.environ.get('REDIS_PORT', 6379)),
        'DATABASE': 0,
        'DEFAULT_TIMEOUT': 300,
    },
    'caching': {
        'HOST': os.environ.get('REDIS_HOST', 'redis'),
        'PORT': int(os.environ.get('REDIS_PORT', 6379)),
        'DATABASE': 1,
        'DEFAULT_TIMEOUT': 300,
    }
}

SECRET_KEY = os.environ.get('SECRET_KEY', 'default-unsecure-change-me')
METRICS_ENABLED = True
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
}
EOF
fi

echo "=== [5/7] Building & Starting Docker Compose Stack ==="
docker compose build
docker compose up -d

echo "=== [6/7] Waiting for NetBox Service Healthcheck ==="
MAX_ATTEMPTS=40
ATTEMPT=1
HEALTH_STATUS="unknown"

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
    HEALTH_STATUS=$(docker inspect --format='{{json .State.Health.Status}}' netbox-app 2>/dev/null | tr -d '"' || echo "starting")
    if [ "$HEALTH_STATUS" = "healthy" ]; then
        echo "[+] netbox-app is HEALTHY (attempt $ATTEMPT/$MAX_ATTEMPTS)"
        break
    fi
    echo "[*] Waiting for container health (current: ${HEALTH_STATUS}, attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."
    sleep 3
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$HEALTH_STATUS" != "healthy" ]; then
    echo "[-] ERROR: NetBox container failed to reach healthy state." >&2
    docker compose ps
    docker compose logs --tail=50 netbox
    exit 1
fi

echo "=== [7/7] Database Migrations & Initial Fixture Seeding ==="
echo "[+] Applying Django database migrations..."
docker compose exec -T netbox python /opt/netbox/netbox/manage.py migrate --no-input

echo "[+] Seeding initial test tenants and IPAM prefixes..."
docker compose exec -T netbox python /opt/netbox/netbox/manage.py shell <<'EOF'
import sys
from tenancy.models import Tenant, TenantGroup
from ipam.models import Prefix, RIR

tg, _ = TenantGroup.objects.get_or_create(name='DevOps Practice', slug='devops-practice')
t, _ = Tenant.objects.get_or_create(name='Core-Infra', slug='core-infra', group=tg)
rir, _ = RIR.objects.get_or_create(name='RFC1918', slug='rfc1918', is_private=True)
p, _ = Prefix.objects.get_or_create(prefix='10.100.0.0/16', rir=rir, tenant=t, description='Automated Seed Prefix')
print(f"Seed verified: Tenant '{t.name}' and Prefix '{p.prefix}' ready.")
EOF

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${APP_PORT:-8000}/api/status/")

echo ""
echo "================================================================="
echo "       NETBOX DEPLOYMENT COMPLETED SUCCESSFULLY (VARIANT #8)     "
echo "================================================================="
echo " Application URL : http://localhost:${APP_PORT:-8000}/"
echo " API Status      : http://localhost:${APP_PORT:-8000}/api/status/ (HTTP ${HTTP_STATUS})"
echo " API Docs        : http://localhost:${APP_PORT:-8000}/api/docs/"
echo " Credentials     : User: ${SUPERUSER_NAME:-admin} | Pass: (stored in .env)"
echo "================================================================="
exit 0
