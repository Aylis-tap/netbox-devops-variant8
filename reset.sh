#!/bin/sh
# reset.sh - Local clean-slate reset utility
echo "=== Tearing down containers, networks and volumes ==="
docker compose down -v --remove-orphans 2>/dev/null || true
echo "=== Removing local .env ==="
rm -f .env
echo "=== Triggering clean setup.sh ==="
/bin/sh setup.sh
