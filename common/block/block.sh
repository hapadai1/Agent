#!/bin/bash
# block.sh - 통합 블록 실행기
# GPT/Claude 블록을 하나의 인터페이스로 실행
#
# 사용법:
#   ./block.sh --type=gpt --action=writer --input=prompt.md --output=content.md
#   ./block.sh --type=claude --action=review --input=content.md --output=decision.json
#
# 공통 인터페이스:
#   --type      : 블록 타입 (gpt, claude)
#   --action    : 액션 이름
#   --input     : 입력 파일 (여러 개 가능)
#   --output    : 출력 파일
#   --config    : 설정 파일

# set -euo pipefail  # source 시 문제 방지

_BLOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOCK_COMMON_DIR="$(dirname "$_BLOCK_DIR")"

# 공통 스크립트 로드
source "$_BLOCK_COMMON_DIR/chatgpt.sh" 2>/dev/null || true
source "$_BLOCK_COMMON_DIR/claude.sh" 2>/dev/null || true

# 블록 스크립트 로드
source "$_BLOCK_DIR/gpt_block.sh"
source "$_BLOCK_DIR/claude_block.sh"

# ══════════════════════════════════════════════════════════════
# 통합 블록 실행
# ══════════════════════════════════════════════════════════════

block_run() {
    local block_type=""
    local args=()

    # --type 추출
    for arg in "$@"; do
        case "$arg" in
            --type=*)
                block_type="${arg#--type=}"
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done

    # 타입 검증
    if [[ -z "$block_type" ]]; then
        echo "ERROR: 블록 타입이 필요합니다 (--type=gpt|claude)" >&2
        return 1
    fi

    # 타입별 실행
    case "$block_type" in
        gpt)
            gpt_block "${args[@]}"
            ;;
        claude)
            claude_block "${args[@]}"
            ;;
        *)
            echo "ERROR: 알 수 없는 블록 타입: $block_type" >&2
            echo "사용 가능: gpt, claude" >&2
            return 1
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 도움말
# ══════════════════════════════════════════════════════════════

show_help() {
    cat <<'EOF'
블록 실행기 - GPT/Claude 통합 인터페이스

사용법:
  ./block.sh --type=TYPE --action=ACTION --input=FILE [옵션...]

필수 옵션:
  --type=TYPE       블록 타입 (gpt, claude)
  --action=ACTION   액션 이름

공통 옵션:
  --input=FILE      입력 파일 (여러 개 가능)
  --output=FILE     출력 파일
  --config=FILE     설정 파일

GPT 블록 옵션:
  --tab=N           ChatGPT 탭 번호
  --timeout=SEC     타임아웃 (기본: 1500)

Claude 블록 옵션:
  --model=MODEL     모델 (sonnet, opus, haiku)
  --template=FILE   프롬프트 템플릿

예시:
  # GPT 작성
  ./block.sh --type=gpt --action=writer \
    --input=prompt.md --output=content.md

  # Claude 검토
  ./block.sh --type=claude --action=review \
    --input=content.md --output=decision.json

  # Claude 최종 판정 (여러 입력)
  ./block.sh --type=claude --action=judge \
    --input=content.md --input=eval.json \
    --output=final.json
EOF
}

# ══════════════════════════════════════════════════════════════
# CLI 실행
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    block_run "$@"
fi
