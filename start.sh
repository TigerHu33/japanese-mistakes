#!/usr/bin/env bash
# 開発環境の起動。冪等: 既に動いているサービスはそのまま。
#   - 各サービスの稼働状況を診断
#   - 不足しているものだけを起動
# Ctrl+C で Vite のみ停止。Docker は別途 `docker compose stop`。
# daemon が固まっている場合は ./restart.sh を案内。

set -e
cd "$(dirname "$0")"
. ./scripts/lib.sh

echo "→ 現状診断:"
print_status

# ---- daemon ----
if ! is_daemon_ok; then
  echo
  echo "✗ Docker daemon が応答しない。 ./restart.sh を実行してください"
  exit 1
fi

# ---- db / api ----
need_compose_up=0
is_container_running db && is_db_healthy || need_compose_up=1
is_container_running api && is_api_healthy || need_compose_up=1

if [ "$need_compose_up" = "1" ]; then
  echo "→ db / api を起動 (docker compose up -d)..."
  docker compose up -d

  echo "→ API ヘルスチェック..."
  for i in $(seq 1 30); do
    if is_api_healthy; then
      echo "  API ready"
      break
    fi
    if [ "$i" = "30" ]; then
      echo "✗ API が 30 秒以内に立ち上がらない。docker compose logs api を確認"
      exit 1
    fi
    sleep 1
  done
else
  echo "  db + api は稼働中。スキップ"
fi

# ---- vite ----
if is_vite_alive; then
  if is_vite_ours; then
    echo
    echo "→ Vite は既に http://localhost:5173 で稼働中。何もしない"
    exit 0
  else
    echo "✗ ポート 5173 が他プロセスに使われている:"
    lsof -nP -iTCP:5173 -sTCP:LISTEN
    exit 1
  fi
fi

cd frontend
if [ ! -d node_modules ]; then
  echo "→ node_modules が無い。npm install を実行..."
  npm install
fi

echo "→ Vite dev server を起動 (http://localhost:5173)..."
exec npm run dev
