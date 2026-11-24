#!/usr/bin/env bash
# Voicebox를 이 포크 그대로 브라우저에서 쓴다 (16GB Apple Silicon Mac용).
#   - 백엔드  http://127.0.0.1:17493  (VOICEBOX_SINGLE_TTS_MODEL=1: TTS 모델은 한 번에 하나만 메모리에)
#   - 화면    http://localhost:5173
# 시스템 여유 메모리가 10% 밑으로 떨어지면 백엔드를 멈춘다. Ctrl+C로 모두 끈다.
# 처음 한 번: backend/venv 준비(README의 setup-python 단계)와 `bun install`.
set -euo pipefail
cd "$(dirname "$0")/.."

export VOICEBOX_SINGLE_TTS_MODEL=1
LOG_DIR=${LOG_DIR:-"$HOME/Library/Logs/voicebox-local"}
mkdir -p "$LOG_DIR"

if curl -sf http://127.0.0.1:17493/health >/dev/null 2>&1; then
  echo "백엔드가 이미 떠 있습니다 (17493). 그대로 씁니다."
  srv=""
else
  backend/venv/bin/uvicorn backend.main:app --port 17493 >>"$LOG_DIR/backend.log" 2>&1 &
  srv=$!
  for _ in $(seq 1 60); do curl -sf http://127.0.0.1:17493/health >/dev/null && break; sleep 1; done
  curl -sf http://127.0.0.1:17493/health >/dev/null || { echo "백엔드가 뜨지 않았습니다. $LOG_DIR/backend.log 를 보세요."; exit 1; }
  ( while kill -0 "$srv" 2>/dev/null; do
      f=$(memory_pressure | tail -1 | grep -o '[0-9]*%' | tr -d %)
      if [ "${f:-100}" -lt 10 ]; then
        echo "[$(date '+%F %T')] 여유 메모리 ${f}% — 백엔드를 멈춥니다" | tee -a "$LOG_DIR/backend.log"
        kill "$srv"
      fi
      sleep 5
    done ) &
  guard=$!
fi

cleanup() { [ -n "${srv:-}" ] && kill "$srv" 2>/dev/null; [ -n "${guard:-}" ] && kill "$guard" 2>/dev/null; true; }
trap cleanup EXIT INT TERM

echo "백엔드 로그: $LOG_DIR/backend.log"
(sleep 3 && open http://localhost:5173) &
cd web && bun run dev --port 5173 --strictPort
