#!/usr/bin/env bash
# 開発環境の停止 (Vite のみ)
#   - 宿主の Vite を kill
#   - db / api は Docker で常駐 (停止しない)
# Docker ごと止めたい場合: `docker compose stop` を別途実行

set +e
cd "$(dirname "$0")"
. ./scripts/lib.sh

echo "→ 起動前の状態:"
print_status
echo

# ポート 5173 を掴んでいるプロセスを特定
PID=$(lsof -nP -iTCP:5173 -sTCP:LISTEN -t 2>/dev/null | head -1)

if [ -z "$PID" ]; then
  echo "→ Vite は動いていない。終了"
  exit 0
fi

# 本プロジェクトの Vite かを確認
CMD=$(ps -p "$PID" -o command= 2>/dev/null)
if ! echo "$CMD" | grep -q "japanese-mistakes/frontend"; then
  echo "✗ ポート 5173 を掴んでいるのは本プロジェクトの Vite ではない:"
  echo "  $CMD"
  echo "  安全のため kill しない。手動で停止してください"
  exit 1
fi

echo "→ Vite (PID $PID) を停止..."
kill "$PID" 2>/dev/null
for i in $(seq 1 5); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
# まだ生きていれば強制
kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null

echo
echo "→ 停止後の状態:"
print_status
