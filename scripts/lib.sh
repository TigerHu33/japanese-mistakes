# 共通ヘルスチェック関数。 start.sh / restart.sh から source される。
# 各関数は exit code でのみ通知 (0=OK, 非0=NG)。出力はしない。

is_daemon_ok() {
  docker info >/dev/null 2>&1
}

# 引数: サービス名 (db / api)
is_container_running() {
  local cid
  cid=$(docker compose ps -q "$1" 2>/dev/null)
  [ -n "$cid" ] && [ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" = "true" ]
}

is_db_healthy() {
  local cid
  cid=$(docker compose ps -q db 2>/dev/null)
  [ -n "$cid" ] && [ "$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null)" = "healthy" ]
}

is_api_healthy() {
  curl -fsS -m 2 -o /dev/null "http://localhost:3000/mistakes?limit=1" 2>/dev/null
}

is_vite_alive() {
  curl -fsS -m 2 -o /dev/null "http://localhost:5173/" 2>/dev/null
}

# 5173 を掴んでいるプロセスが本プロジェクトの Vite かどうか
is_vite_ours() {
  local pid
  pid=$(lsof -nP -iTCP:5173 -sTCP:LISTEN -t 2>/dev/null | head -1)
  [ -n "$pid" ] && ps -p "$pid" -o command= 2>/dev/null | grep -q "japanese-mistakes/frontend"
}

# 状態をまとめて表示
print_status() {
  local d="✗" db="✗" api="✗" vite="✗"
  is_daemon_ok && d="✓"
  is_container_running db && is_db_healthy && db="✓"
  is_container_running api && is_api_healthy && api="✓"
  is_vite_alive && vite="✓"
  printf "  %s daemon\n  %s db\n  %s api\n  %s vite\n" "$d" "$db" "$api" "$vite"
}
