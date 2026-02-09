#!/bin/bash
# validator.sh - 입력값 검증 함수

validate_project_name() {
    local name="$1"

    # 빈 값 체크
    if [[ -z "$name" ]]; then
        echo "오류: 프로젝트 이름이 비어있습니다." >&2
        return 1
    fi

    # 영문, 숫자, 언더스코어만 허용
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        echo "오류: 프로젝트 이름은 영문으로 시작하고, 영문/숫자/_만 포함해야 합니다." >&2
        return 1
    fi

    # 길이 체크 (2-50자)
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        echo "오류: 프로젝트 이름은 2-50자 사이여야 합니다." >&2
        return 1
    fi

    return 0
}

validate_sections() {
    local -a sections=("$@")

    if [[ ${#sections[@]} -eq 0 ]]; then
        echo "경고: Step이 정의되지 않았습니다." >&2
        return 1
    fi

    return 0
}
