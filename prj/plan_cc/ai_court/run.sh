#!/bin/bash
# prj/plan_cc/ai_court/run.sh
# AI 법원 경매 사업계획서 프로젝트 실행 스크립트

set -e

# ══════════════════════════════════════════════════════════════
# 프로젝트 정보 설정
# ══════════════════════════════════════════════════════════════
export PROJECT_NAME="ai_court"
export PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
export CORE_DIR="$(cd "$PROJECT_DIR/../../_core" && pwd)"

# ══════════════════════════════════════════════════════════════
# 공통 설정 로드
# ══════════════════════════════════════════════════════════════
source "$CORE_DIR/base.sh"

# 프로젝트별 설정 로드
if [[ -f "$CONFIG_DIR/settings.sh" ]]; then
    source "$CONFIG_DIR/settings.sh"
fi

# ══════════════════════════════════════════════════════════════
# 메인 로직
# ══════════════════════════════════════════════════════════════
main() {
    # 프로젝트 초기화
    init_project || return 1

    log_info "Starting $PROJECT_NAME project"
    log_info "Using CORE_DIR: $CORE_DIR"

    # 코어 라이브러리 로드 (suite_runner)
    load_core_lib suite_runner || return 1

    # 실제 실행 - _core의 스크립트 호출
    # section_runner.sh는 _core/scripts에서 실행
    "$CORE_DIR/scripts/section_runner.sh" "$@"
}

# 메인 실행
main "$@"
