#!/bin/sh
set -e

BASE_URL="http://localhost:8000"
TOKEN="0123456789abcdef0123456789abcdef01234567"
FAILED_TESTS=0

check_endpoint() {
    TARGET_URL="$1"
    NAME="$2"
    EXPECTED="$3"

    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Token $TOKEN" "$TARGET_URL")

    MATCH=0
    case "$EXPECTED" in
        *"$CODE"*) MATCH=1 ;;
    esac

    if [ "$MATCH" -eq 1 ]; then
        echo "[OK] GET $NAME -> HTTP $CODE (Expected $EXPECTED)"
    else
        echo "[FAIL] GET $NAME -> HTTP $CODE (got $CODE)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

echo "================================================="
echo " Starting NetBox Smoke Test Suite (POSIX sh)...   "
echo " Target: $BASE_URL"
echo "================================================="

check_endpoint "$BASE_URL/api/status/" "/api/status/" "200"
check_endpoint "$BASE_URL/api/schema/" "/api/schema/" "200"
check_endpoint "$BASE_URL/api/tenancy/tenants/" "/api/tenancy/tenants/" "200"
check_endpoint "$BASE_URL/api/ipam/prefixes/" "/api/ipam/prefixes/" "200"
check_endpoint "$BASE_URL/login/" "/login/" "200 302"
check_endpoint "$BASE_URL/metrics" "/metrics" "200"

echo "-------------------------------------------------"
if [ "$FAILED_TESTS" -eq 0 ]; then
    echo "[SUCCESS] All smoke tests passed successfully (0 failures)."
    exit 0
else
    echo "[ERROR] Smoke test suite encountered $FAILED_TESTS failure(s)." >&2
    exit 1
fi
