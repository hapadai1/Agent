#!/bin/bash
# init.sh - lib/core 모듈 일괄 로드
# 사용법: source lib/core/init.sh
#
# 모든 core 모듈을 로드합니다:
#   - json.sh    : JSON 처리
#   - yaml.sh    : YAML 처리
#   - validate.sh: 입력 검증
#   - deps.sh    : 의존성 검증
#   - subprocess.sh: 서브프로세스 실행

_INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 모듈 로드
# ══════════════════════════════════════════════════════════════

# 핵심 모듈 로드 순서 (의존성 순)
_CORE_MODULES=(
    "deps"
    "validate"
    "json"
    "yaml"
    "subprocess"
)

for module in "${_CORE_MODULES[@]}"; do
    module_path="${_INIT_DIR}/${module}.sh"
    if [[ -f "$module_path" ]]; then
        # shellcheck source=/dev/null
        source "$module_path"
    else
        echo "WARN: lib/core/${module}.sh 를 찾을 수 없습니다" >&2
    fi
done

# ══════════════════════════════════════════════════════════════
# 초기화 검증
# ══════════════════════════════════════════════════════════════

# 필수 의존성 확인
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3가 설치되어 있지 않습니다" >&2
    echo "  설치: brew install python3" >&2
fi

# ══════════════════════════════════════════════════════════════
# 정보 출력
# ══════════════════════════════════════════════════════════════

# 로드된 모듈 정보 (DEBUG 모드에서만)
if [[ "${LOG_LEVEL:-}" == "DEBUG" ]]; then
    echo "lib/core 모듈 로드 완료:" >&2
    for module in "${_CORE_MODULES[@]}"; do
        echo "  - ${module}.sh" >&2
    done
fi
