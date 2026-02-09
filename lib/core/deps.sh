#!/bin/bash
# deps.sh - 모듈 의존성 검증
# 사용법: source lib/core/deps.sh

# ══════════════════════════════════════════════════════════════
# 전역 변수
# ══════════════════════════════════════════════════════════════

# lib/core 디렉토리 경로
_LIB_CORE_DIR="${_LIB_CORE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
_LIB_ROOT_DIR="$(dirname "$_LIB_CORE_DIR")"

# 로드된 모듈 추적 (중복 로드 방지)
declare -a _LOADED_MODULES=()

# ══════════════════════════════════════════════════════════════
# 명령어 의존성 검증
# ══════════════════════════════════════════════════════════════

# 명령어 존재 확인
# 사용법: require_command "python3" "jq"
require_command() {
    local missing=()

    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: 필수 명령어가 설치되어 있지 않습니다: ${missing[*]}" >&2
        echo "  설치 방법:" >&2
        for cmd in "${missing[@]}"; do
            case "$cmd" in
                python3)
                    echo "    brew install python3" >&2
                    ;;
                jq)
                    echo "    brew install jq" >&2
                    ;;
                yq)
                    echo "    brew install yq" >&2
                    ;;
                *)
                    echo "    brew install $cmd" >&2
                    ;;
            esac
        done
        return 1
    fi
    return 0
}

# 명령어 버전 확인
# 사용법: require_command_version "python3" "3.8"
require_command_version() {
    local cmd="$1"
    local min_version="$2"

    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd 명령어가 설치되어 있지 않습니다" >&2
        return 1
    fi

    local current_version
    case "$cmd" in
        python3|python)
            current_version=$($cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            ;;
        node)
            current_version=$($cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            ;;
        *)
            current_version=$($cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
            ;;
    esac

    if [[ -z "$current_version" ]]; then
        echo "WARN: $cmd 버전을 확인할 수 없습니다" >&2
        return 0
    fi

    # 버전 비교 (간단한 비교)
    if [[ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" != "$min_version" ]]; then
        echo "ERROR: $cmd 버전이 너무 낮습니다 (현재: $current_version, 최소: $min_version)" >&2
        return 1
    fi

    return 0
}

# ══════════════════════════════════════════════════════════════
# 모듈 의존성 검증
# ══════════════════════════════════════════════════════════════

# 모듈이 이미 로드되었는지 확인
# 사용법: if module_loaded "json"; then ...
module_loaded() {
    local module="$1"

    for loaded in "${_LOADED_MODULES[@]}"; do
        if [[ "$loaded" == "$module" ]]; then
            return 0
        fi
    done
    return 1
}

# 모듈 로드
# 사용법: require_module "json" "validate"
require_module() {
    local missing=()

    for module in "$@"; do
        # 이미 로드되었으면 스킵
        if module_loaded "$module"; then
            continue
        fi

        local module_path="${_LIB_CORE_DIR}/${module}.sh"

        if [[ ! -f "$module_path" ]]; then
            missing+=("$module")
            continue
        fi

        # 모듈 로드
        # shellcheck source=/dev/null
        source "$module_path"
        _LOADED_MODULES+=("$module")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: 모듈을 찾을 수 없습니다: ${missing[*]}" >&2
        echo "  경로: $_LIB_CORE_DIR" >&2
        return 1
    fi
    return 0
}

# 프로젝트별 모듈 로드
# 사용법: require_project_module "ai_court" "state" "parser"
require_project_module() {
    local project="$1"
    shift
    local missing=()

    local project_lib="${_LIB_ROOT_DIR}/../claude/${project}/lib/util"

    for module in "$@"; do
        local module_path="${project_lib}/${module}.sh"

        if [[ ! -f "$module_path" ]]; then
            missing+=("$module")
            continue
        fi

        # 이미 로드되었으면 스킵
        if module_loaded "${project}_${module}"; then
            continue
        fi

        # 모듈 로드
        # shellcheck source=/dev/null
        source "$module_path"
        _LOADED_MODULES+=("${project}_${module}")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: 프로젝트 모듈을 찾을 수 없습니다: ${missing[*]}" >&2
        echo "  프로젝트: $project" >&2
        echo "  경로: $project_lib" >&2
        return 1
    fi
    return 0
}

# ══════════════════════════════════════════════════════════════
# 환경 검증
# ══════════════════════════════════════════════════════════════

# 환경 변수 존재 확인
# 사용법: require_env "PROJECT_DIR" "API_KEY"
require_env() {
    local missing=()

    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: 필수 환경 변수가 설정되지 않았습니다: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# 환경 변수 기본값 설정
# 사용법: default_env "LOG_LEVEL" "INFO"
default_env() {
    local var="$1"
    local default="$2"

    if [[ -z "${!var:-}" ]]; then
        export "$var"="$default"
    fi
}

# ══════════════════════════════════════════════════════════════
# 초기화 헬퍼
# ══════════════════════════════════════════════════════════════

# 기본 의존성 검증 (python3 필수)
# 사용법: init_core_deps
init_core_deps() {
    require_command "python3" || return 1

    # 기본 환경 변수 설정
    default_env "LOG_LEVEL" "INFO"

    return 0
}

# 전체 의존성 검증 (모든 옵션 도구 포함)
# 사용법: init_full_deps
init_full_deps() {
    require_command "python3" || return 1

    # jq는 선택사항 (없으면 Python fallback)
    if ! command -v jq &>/dev/null; then
        echo "INFO: jq가 설치되어 있지 않습니다. Python을 사용합니다." >&2
    fi

    return 0
}

# 로드된 모듈 목록 출력
# 사용법: list_loaded_modules
list_loaded_modules() {
    echo "로드된 모듈:"
    for module in "${_LOADED_MODULES[@]}"; do
        echo "  - $module"
    done
}
