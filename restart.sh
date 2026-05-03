#!/usr/bin/env bash
# 個別サービスの復旧スクリプト。壊れているものだけ修復する。
#   - 全部正常 → 何もしない
#   - daemon NG → Docker Desktop を完全再起動 (最終手段)
#   - container NG → `docker compose restart <svc>` だけ
#   - vite NG → Vite だけ kill + 再起動 (start.sh 経由)
# Docker Desktop の再起動は daemon NG の時のみ。

set +e
cd "$(dirname "$0")"
. ./scripts/lib.sh

echo "→ 起動前の状態:"
print_status
echo

# ---- 1. daemon ----
if ! is_daemon_ok; then
  echo "✗ Docker daemon が応答しない → Docker Desktop を再起動"

  echo "  滞留 docker CLI を kill..."
  pkill -9 -f "docker compose" 2>/dev/null
  pkill -9 -f "docker (info|start|stats)" 2>/dev/null
  sleep 1

  echo "  Docker Desktop を終了..."
  osascript -e 'quit app "Docker Desktop"' 2>/dev/null
  osascript -e 'quit app "Docker"' 2>/dev/null
  for i in $(seq 1 15); do
    pgrep -f "/Applications/Docker.app/" >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -f "/Applications/Docker.app/" >/dev/null 2>&1; then
    pkill -9 -f "/Applications/Docker.app/" 2>/dev/null
    sleep 2
  fi

  echo "  Docker Desktop を起動..."
  open -a Docker
  for i in $(seq 1 10); do
    pgrep -f "/Applications/Docker.app/" >/dev/null 2>&1 && break
    sleep 1
  done
  pgrep -f "/Applications/Docker.app/" >/dev/null 2>&1 || { sleep 3; open -a Docker; }

  echo "  daemon ready 待機 (最大 5 分)..."
  for i in $(seq 1 100); do
    is_daemon_ok && { echo "  daemon ready (${i}x3s)"; break; }
    [ "$i" = "100" ] && { echo "✗ 5 分待っても daemon 未応答。手動確認"; exit 1; }
    sleep 3
  done
fi

# ---- 2. container 個別修復 ----
if ! { is_container_running db && is_db_healthy; }; then
  echo "✗ db NG → docker compose up -d db で立て直し"
  docker compose up -d db
  for i in $(seq 1 30); do
    is_db_healthy && break
    sleep 1
  done
fi

if ! { is_container_running api && is_api_healthy; }; then
  echo "✗ api NG → docker compose up -d api で立て直し"
  docker compose up -d api
  for i in $(seq 1 30); do
    is_api_healthy && break
    sleep 1
  done
fi

# ---- 3. vite ----
if is_vite_alive && is_vite_ours; then
  echo "→ Vite は稼働中だが restart 指示のため kill して再起動"
  PID=$(lsof -nP -iTCP:5173 -sTCP:LISTEN -t 2>/dev/null | head -1)
  [ -n "$PID" ] && kill -9 "$PID"
  sleep 1
fi

echo
echo "→ 修復後の状態:"
print_status
echo
echo "→ start.sh に exec して Vite を起動..."
exec ./start.sh
