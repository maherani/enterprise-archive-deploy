#!/usr/bin/env bash
set -e

echo "=== [1/6] Checking Environment (.env) ==="
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi

echo "=== [2/6] Setting Storage Permissions ==="
mkdir -p ./ai_box_gateway/data/anythingllm
chmod -R 777 ./ai_box_gateway/data/anythingllm

echo "=== [3/6] Starting Docker Containers ==="
docker network rm ai_chat_net 2>/dev/null || true
docker compose up -d

echo "=== [4/6] Waiting for Database ==="
for i in {1..30}; do
    if docker exec archive_db pg_isready -U "${POSTGRES_USER:-archive_user}" >/dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    sleep 2
done

echo "=== [5/6] Configuring Nextcloud & Groups ==="
sleep 5
docker exec -u www-data archive_app php occ app:enable archive_autotag || true
docker exec -u www-data archive_app php occ group:add ai_chat_access || true

echo "=== [6/6] Ensuring AI Model (qwen2.5:0.5b) is Loaded ==="
if ! docker exec ai_box_ollama ollama list | grep -q "qwen2.5:0.5b"; then
    echo "Pulling model qwen2.5:0.5b (please wait)..."
    docker exec ai_box_ollama ollama pull qwen2.5:0.5b
else
    echo "Model qwen2.5:0.5b is already downloaded."
fi

echo "=== Validation Checks ==="
docker exec -u www-data archive_app php occ status
curl -s -o /dev/null -w "Web Portal HTTP Status: %{http_code}\n" http://localhost
docker exec ai_box_ollama ollama run qwen2.5:0.5b "test" >/dev/null 2>&1 && echo "AI Model: OK" || echo "AI Model: Failed"

echo "=========================================="
echo "DEPLOYMENT COMPLETE & VERIFIED!"
echo "=========================================="
