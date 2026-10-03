#!/usr/bin/env bash
# Deploys one release on the alpha VM: `sudo /opt/bio_siege/deploy.sh <image tag>`.
# Reads the non-secret config written by the startup script, pulls the secrets from Secret Manager into a
# root-only .env, then starts the stack and waits for the health checks.
set -euo pipefail

TAG="${1:?usage: deploy.sh <image tag>}"
APP_DIR=/opt/bio_siege
cd "$APP_DIR"

# shellcheck source=/dev/null
source "$APP_DIR/instance.env"

secret() {
	gcloud secrets versions access latest --secret="$1" --project="$PROJECT_ID"
}

DB_PASSWORD=$(secret db-password)
# DB_HOST=postgres means the database runs in this stack (Terraform database = "vm").
PROFILES=""
[ "$DB_HOST" = "postgres" ] && PROFILES="vm-db"

umask 077
cat > .env.tmp <<EOF
COMPOSE_PROFILES=${PROFILES}
POSTGRES_PASSWORD=${DB_PASSWORD}
NAKAMA_IMAGE=${REGISTRY}/nakama:${TAG}
WORKER_IMAGE=${REGISTRY}/worker:${TAG}
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
DB_ADDRESS=nakama:${DB_PASSWORD}@${DB_HOST}:5432/nakama
SERVER_KEY=$(secret nakama-server-key)
HTTP_KEY=$(secret nakama-http-key)
SESSION_ENCRYPTION_KEY=$(secret nakama-session-encryption-key)
SESSION_REFRESH_KEY=$(secret nakama-session-refresh-key)
CONSOLE_USERNAME=${CONSOLE_USERNAME}
CONSOLE_PASSWORD=$(secret nakama-console-password)
CONSOLE_SIGNING_KEY=$(secret nakama-console-signing-key)
EOF
mv .env.tmp .env

docker compose pull --quiet
docker compose up -d --remove-orphans --wait --wait-timeout 180
echo "$TAG" > release
docker image prune -f >/dev/null
echo "deploy.sh: release $TAG is up"
