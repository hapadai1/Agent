#!/bin/bash
# ChatGPT 공통 타임아웃 및 재시도 설정
# 모든 ChatGPT 호출에서 이 설정을 사용합니다.

# ══════════════════════════════════════════════════════════════
# 타임아웃 설정
# ══════════════════════════════════════════════════════════════

# 1회 대기 시간 (초) - 초기 폴링 대기
export CHATGPT_WAIT_SEC="${CHATGPT_WAIT_SEC:-90}"

# 추가 대기 단위 (초) - 스트리밍 중 추가 대기
export CHATGPT_EXTRA_WAIT="${CHATGPT_EXTRA_WAIT:-120}"

# 추가 대기 횟수 - 추가 대기 반복 횟수
export CHATGPT_EXTRA_ROUNDS="${CHATGPT_EXTRA_ROUNDS:-3}"

# ══════════════════════════════════════════════════════════════
# 재시도 설정
# ══════════════════════════════════════════════════════════════

# 최대 재시도 횟수
export CHATGPT_MAX_RETRIES="${CHATGPT_MAX_RETRIES:-3}"

# 최소 응답 길이 (이보다 짧으면 실패로 간주)
export CHATGPT_MIN_RESPONSE_LEN="${CHATGPT_MIN_RESPONSE_LEN:-10}"

# 재시도 전 대기 시간 (초)
export CHATGPT_RETRY_DELAY="${CHATGPT_RETRY_DELAY:-2}"

# ══════════════════════════════════════════════════════════════
# 세션 상태 관리 (챕터 변경 시 자동 new chat)
# ══════════════════════════════════════════════════════════════

# 세션 상태 파일 디렉토리
export CHATGPT_SESSION_DIR="${CHATGPT_SESSION_DIR:-/tmp/chatgpt_sessions}"

# 세션 상태 자동 관리 활성화 (true/false)
export CHATGPT_AUTO_NEW_CHAT="${CHATGPT_AUTO_NEW_CHAT:-true}"

# ══════════════════════════════════════════════════════════════
# 계산된 값 (참고용)
# ══════════════════════════════════════════════════════════════
# 1회 시도 최대: CHATGPT_WAIT_SEC + (CHATGPT_EXTRA_WAIT × CHATGPT_EXTRA_ROUNDS)
#              = 90 + (120 × 3) = 450초 = 7.5분
# 총 최대 시간: 7.5분 × CHATGPT_MAX_RETRIES = 7.5 × 3 = 22.5분
