#!/bin/bash
# prompts.sh - 사용자 입력 프롬프트 함수

prompt_project_name() {
    local name
    while true; do
        read -rp "  프로젝트 ID (영문, 숫자, _만 허용): " name
        if [[ -n "$name" ]]; then
            echo "$name"
            return 0
        fi
        echo "  → 프로젝트 ID를 입력해주세요." >&2
    done
}

prompt_display_name() {
    local name
    read -rp "  표시 이름 (한글 가능): " name
    if [[ -z "$name" ]]; then
        name="새 프로젝트"
    fi
    echo "$name"
}

prompt_description() {
    local desc
    read -rp "  설명: " desc
    if [[ -z "$desc" ]]; then
        desc="프로젝트 설명"
    fi
    echo "$desc"
}
