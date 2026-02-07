#!/bin/bash
# override.sh - Flow 변수 오버라이드 처리 (bash 3.2 호환)
# CLI 인자, 환경변수, config 파일에서 변수를 수집하여 우선순위대로 적용

OVERRIDE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 변수 저장소 (파일 기반 - bash 3.2 호환)
# ══════════════════════════════════════════════════════════════

# 임시 파일로 변수 저장
OVERRIDE_VARS_FILE="${TMPDIR:-/tmp}/override_vars_$$"

# 초기화
_override_init() {
    rm -f "$OVERRIDE_VARS_FILE"
    touch "$OVERRIDE_VARS_FILE"
}

# 변수 설정
override_set() {
    local key="$1"
    local value="$2"

    # 기존 값 제거 후 추가
    if [[ -f "$OVERRIDE_VARS_FILE" ]]; then
        grep -v "^${key}=" "$OVERRIDE_VARS_FILE" > "${OVERRIDE_VARS_FILE}.tmp" 2>/dev/null || true
        mv "${OVERRIDE_VARS_FILE}.tmp" "$OVERRIDE_VARS_FILE"
    fi
    echo "${key}=${value}" >> "$OVERRIDE_VARS_FILE"
}

# 변수 가져오기
override_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$OVERRIDE_VARS_FILE" ]]; then
        local value
        value=$(grep "^${key}=" "$OVERRIDE_VARS_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    echo "$default"
}

# 변수 존재 확인
override_has() {
    local key="$1"
    [[ -f "$OVERRIDE_VARS_FILE" ]] && grep -q "^${key}=" "$OVERRIDE_VARS_FILE" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# CLI 인자 파싱
# ══════════════════════════════════════════════════════════════

override_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --var=*|--set=*)
                local kv="${1#*=}"
                local key="${kv%%=*}"
                local value="${kv#*=}"
                override_set "$key" "$value"
                echo "Override: $key=$value" >&2
                shift
                ;;
            --var|--set)
                if [[ -n "$2" ]]; then
                    local key="${2%%=*}"
                    local value="${2#*=}"
                    override_set "$key" "$value"
                    echo "Override: $key=$value" >&2
                    shift 2
                else
                    shift
                fi
                ;;
            *)
                shift
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# 환경변수에서 로드
# ══════════════════════════════════════════════════════════════

override_load_env() {
    while IFS='=' read -r name value; do
        if [[ "$name" == AGENT_VAR_* ]]; then
            local key="${name#AGENT_VAR_}"
            key=$(echo "$key" | tr '[:upper:]' '[:lower:]')

            if ! override_has "$key"; then
                override_set "$key" "$value"
                echo "Env override: $key=$value" >&2
            fi
        fi
    done < <(env)
}

# ══════════════════════════════════════════════════════════════
# Config 파일에서 로드
# ══════════════════════════════════════════════════════════════

override_load_config() {
    local config_file="${1:-${PROJECT_DIR}/config.yaml}"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    python3 -c "
import yaml
import os

config_file = '$config_file'

with open(config_file, 'r', encoding='utf-8') as f:
    config = yaml.safe_load(f) or {}

variables = config.get('variables', {})
for key, value in variables.items():
    print(f'{key}={value}')
" 2>/dev/null | while IFS='=' read -r key value; do
        if ! override_has "$key"; then
            override_set "$key" "$value"
        fi
    done
}

# ══════════════════════════════════════════════════════════════
# Flow 기본값 로드
# ══════════════════════════════════════════════════════════════

override_load_flow_defaults() {
    local flow_file="${1:-${PROJECT_DIR}/flow.yaml}"

    if [[ ! -f "$flow_file" ]]; then
        return 0
    fi

    python3 -c "
import yaml

flow_file = '$flow_file'

with open(flow_file, 'r', encoding='utf-8') as f:
    flow = yaml.safe_load(f) or {}

variables = flow.get('variables', {})
for key, var_def in variables.items():
    if isinstance(var_def, dict):
        default = var_def.get('default', '')
        if default:
            print(f'{key}={default}')
    else:
        print(f'{key}={var_def}')
" 2>/dev/null | while IFS='=' read -r key value; do
        if ! override_has "$key"; then
            override_set "$key" "$value"
        fi
    done
}

# ══════════════════════════════════════════════════════════════
# 통합 로드
# ══════════════════════════════════════════════════════════════

override_load() {
    local config_path=""
    local flow_path=""
    local cli_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config=*)
                config_path="${1#--config=}"
                shift
                ;;
            --flow=*)
                flow_path="${1#--flow=}"
                shift
                ;;
            --var=*|--set=*)
                cli_args+=("$1")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 우선순위 역순으로 로드 (낮은 것부터)
    if [[ -n "$flow_path" ]]; then
        override_load_flow_defaults "$flow_path"
    elif [[ -n "$PROJECT_DIR" ]]; then
        override_load_flow_defaults "${PROJECT_DIR}/flow.yaml"
    fi

    if [[ -n "$config_path" ]]; then
        override_load_config "$config_path"
    elif [[ -n "$PROJECT_DIR" ]]; then
        override_load_config "${PROJECT_DIR}/config.yaml"
    fi

    override_load_env
    override_parse_args "${cli_args[@]}"
}

# ══════════════════════════════════════════════════════════════
# 모든 변수 출력
# ══════════════════════════════════════════════════════════════

override_list() {
    echo "Override Variables:"
    echo ""

    if [[ -f "$OVERRIDE_VARS_FILE" ]]; then
        while IFS='=' read -r key value; do
            if [[ ${#value} -gt 50 ]]; then
                value="${value:0:47}..."
            fi
            printf "  %-20s = %s\n" "$key" "$value"
        done < "$OVERRIDE_VARS_FILE"
    fi
}

# ══════════════════════════════════════════════════════════════
# 문자열 치환
# ══════════════════════════════════════════════════════════════

override_substitute() {
    local text="$1"
    local result="$text"

    if [[ -f "$OVERRIDE_VARS_FILE" ]]; then
        while IFS='=' read -r key value; do
            result="${result//\{$key\}/$value}"
        done < "$OVERRIDE_VARS_FILE"
    fi

    echo "$result"
}

override_substitute_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    local content=$(cat "$file")
    override_substitute "$content"
}

# ══════════════════════════════════════════════════════════════
# 환경변수로 내보내기
# ══════════════════════════════════════════════════════════════

override_export() {
    local count=0
    if [[ -f "$OVERRIDE_VARS_FILE" ]]; then
        while IFS='=' read -r key value; do
            local env_key="FLOW_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
            export "$env_key"="$value"
            ((count++))
        done < "$OVERRIDE_VARS_FILE"
    fi
    echo "Exported $count variables to environment" >&2
}

# ══════════════════════════════════════════════════════════════
# 초기화/정리
# ══════════════════════════════════════════════════════════════

override_clear() {
    rm -f "$OVERRIDE_VARS_FILE"
    touch "$OVERRIDE_VARS_FILE"
    echo "Override variables cleared" >&2
}

# 스크립트 종료 시 정리
_override_cleanup() {
    rm -f "$OVERRIDE_VARS_FILE" "${OVERRIDE_VARS_FILE}.tmp" 2>/dev/null
}
trap _override_cleanup EXIT

# 초기화
_override_init

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Override Manager - Flow 변수 오버라이드 (bash 3.2 호환)"
    echo ""
    echo "우선순위 (높은 순):"
    echo "  1. CLI 인자 (--var=key=value)"
    echo "  2. 환경변수 (AGENT_VAR_*)"
    echo "  3. config.yaml"
    echo "  4. flow.yaml defaults"
fi
