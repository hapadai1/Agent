#!/bin/bash
# run.sh - dev_plan 진입점
# 설계와 개발 Phase를 통합 관리
#
# 사용법:
#   ./run.sh --phase=design                      # 설계 루프 실행
#   ./run.sh --phase=design --version=2           # 설계 v2부터 시작
#   ./run.sh --phase=design --dry-run             # 설계 테스트
#   ./run.sh --phase=eval --version=1             # GPT 테스트 평가 요청
#   ./run.sh --phase=eval --version=1 --dry-run   # 평가 테스트
#   ./run.sh --status                             # 현재 상태 출력

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════
PHASE=""
VERSION=""
DRY_RUN=""
STATUS=false
EXTRA_ARGS=()

show_help() {
    echo ""
    echo "run.sh - dev_plan 진입점"
    echo ""
    echo "사용법: ./run.sh --phase=PHASE [옵션]"
    echo ""
    echo "Phase:"
    echo "  design     설계 루프 (GPT 작성 → Claude 평가, 자동 반복)"
    echo "  eval       GPT 테스트 평가 요청 (--version 필수)"
    echo ""
    echo "옵션:"
    echo "  --phase=PHASE   실행할 Phase (design, eval)"
    echo "  --version=N     버전 번호"
    echo "  --dry-run       테스트 모드"
    echo "  --once          1회만 실행 (design)"
    echo "  --status        현재 상태 출력"
    echo "  --help          도움말 표시"
    echo ""
    echo "예시:"
    echo "  ./run.sh --phase=design                    # 설계 자동 반복"
    echo "  ./run.sh --phase=design --version=2        # v2부터 시작"
    echo "  ./run.sh --phase=design --dry-run          # 설계 테스트"
    echo "  ./run.sh --phase=eval --version=1          # v1 테스트 평가"
    echo "  ./run.sh --status                          # 상태 확인"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --phase=*)
            PHASE="${1#*=}"
            shift
            ;;
        --version=*)
            VERSION="$1"
            EXTRA_ARGS+=("$1")
            shift
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            EXTRA_ARGS+=("--dry-run")
            shift
            ;;
        --once)
            EXTRA_ARGS+=("--once")
            shift
            ;;
        --status)
            STATUS=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════
# 상태 출력
# ══════════════════════════════════════════════════════════════
if [[ "$STATUS" == "true" ]]; then
    STATE_FILE="${SCRIPT_DIR}/runtime/state/current.json"
    if [[ -f "$STATE_FILE" ]]; then
        echo "━━━ 현재 상태 ━━━"
        python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    data = json.load(f)
print(json.dumps(data, ensure_ascii=False, indent=2))
" 2>/dev/null || cat "$STATE_FILE"
    else
        echo "상태 파일 없음: $STATE_FILE"
    fi
    exit 0
fi

# ══════════════════════════════════════════════════════════════
# Phase 실행
# ══════════════════════════════════════════════════════════════
if [[ -z "$PHASE" ]]; then
    echo "ERROR: --phase는 필수입니다." >&2
    show_help
    exit 1
fi

case "$PHASE" in
    design)
        echo "설계 Phase 시작..."
        exec "${SCRIPT_DIR}/scripts/design_runner.sh" "${EXTRA_ARGS[@]}"
        ;;
    eval|dev)
        echo "테스트 평가 Phase 시작..."
        exec "${SCRIPT_DIR}/scripts/eval_runner.sh" "${EXTRA_ARGS[@]}"
        ;;
    *)
        echo "ERROR: 알 수 없는 Phase: $PHASE" >&2
        echo "사용 가능: design, eval" >&2
        exit 1
        ;;
esac
