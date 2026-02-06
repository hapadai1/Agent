#!/bin/bash
# prompt_critic.sh - Prompt Critic 호출 및 패치 제안 관리
# Phase 4: 프롬프트 자동개선 시스템

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"
COMMON_DIR="$(dirname "$(dirname "$PROJECT_DIR")")/common"

# 의존성 로드
source "${SCRIPT_DIR}/prompt_loader.sh"
source "${LIB_DIR}/eval/defect_tracker.sh"
source "${LIB_DIR}/eval/trigger_checker.sh"
source "${LIB_DIR}/util/sections.sh" 2>/dev/null || true

# ChatGPT 자동화 스크립트 (Tab3 사용)
CHATGPT_SCRIPT="${COMMON_DIR}/chatgpt.sh"

# 패치 저장 파일
PATCHES_DIR="${PROJECT_DIR}/prompts/patches"
PENDING_PATCHES_FILE="${PATCHES_DIR}/pending.json"
CHANGELOG_FILE="${PROJECT_DIR}/logs/prompt_changelog.md"

# Tab5 설정 (프롬프트 개선용)
CRITIC_WINDOW="${CRITIC_WINDOW:-1}"
CRITIC_TAB="${CRITIC_TAB:-5}"
CRITIC_TIMEOUT="${CRITIC_TIMEOUT:-180}"

# ══════════════════════════════════════════════════════════════
# Critic 프롬프트 생성
# ══════════════════════════════════════════════════════════════

# Critic 프롬프트 로드
load_critic_prompt() {
    local section_id="$1"
    local writer_version="${2:-$(get_active_writer_version)}"

    local yaml_file="${VERSIONS_DIR}/critic_v1.yaml"

    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: Critic prompt file not found: $yaml_file" >&2
        return 1
    fi

    # 섹션 정보
    local section_name
    section_name=$(get_section_name "$section_id" 2>/dev/null || echo "$section_id")

    # Writer 프롬프트 가져오기
    local writer_prompt
    writer_prompt=$(load_writer_prompt "$section_id" "사업계획서 주제" "" "")

    # 최근 통계 가져오기
    local stats
    stats=$(analyze_defect_history "$section_id" 5)

    # 값 추출
    local latest_score avg_score score_trend top_tags consecutive_tags
    latest_score=$(echo "$stats" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('latest_score', 0))")
    avg_score=$(echo "$stats" | python3 -c "import json,sys; d=json.load(sys.stdin); print(round(d.get('avg_score', 0), 1))")
    score_trend=$(echo "$stats" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('score_trend', 'unknown'))")
    top_tags=$(echo "$stats" | python3 -c "import json,sys; d=json.load(sys.stdin); print(', '.join(d.get('top_tags', [])))")
    consecutive_tags=$(echo "$stats" | python3 -c "import json,sys; d=json.load(sys.stdin); print(', '.join(d.get('consecutive_tags', [])))")

    # 최근 평가에서 defect_tags와 priority_fix 가져오기
    local latest_defect_tags priority_fix
    latest_defect_tags=$(echo "$stats" | python3 -c "import json,sys; d=json.load(sys.stdin); tags=d.get('tag_frequency', {}); print(', '.join(tags.keys()))")

    # YAML에서 프롬프트 구성요소 로드
    local role task_header input_template analysis_instruction output_format
    role=$(yaml_get_multiline "$yaml_file" "skeleton.role")
    task_header=$(yaml_get_multiline "$yaml_file" "skeleton.task_header")
    task_header="${task_header//\{section_name\}/$section_name}"

    input_template=$(yaml_get_multiline "$yaml_file" "skeleton.input_template")
    input_template="${input_template//\{writer_version\}/$writer_version}"
    input_template="${input_template//\{writer_prompt\}/$writer_prompt}"
    input_template="${input_template//\{latest_score\}/$latest_score}"
    input_template="${input_template//\{defect_tags\}/$latest_defect_tags}"
    input_template="${input_template//\{priority_fix\}/자동 분석}"
    input_template="${input_template//\{k\}/5}"
    input_template="${input_template//\{avg_score\}/$avg_score}"
    input_template="${input_template//\{score_trend\}/$score_trend}"
    input_template="${input_template//\{top_tags\}/$top_tags}"
    input_template="${input_template//\{consecutive_tags\}/$consecutive_tags}"

    analysis_instruction=$(yaml_get_multiline "$yaml_file" "skeleton.analysis_instruction")
    output_format=$(yaml_get_multiline "$yaml_file" "skeleton.output_format")

    # 프롬프트 조합
    local prompt="$role"
    prompt+=$'\n\n'"$task_header"
    prompt+=$'\n\n'"$input_template"
    prompt+=$'\n\n'"$analysis_instruction"
    prompt+=$'\n\n'"$output_format"

    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# Critic 호출
# ══════════════════════════════════════════════════════════════

# Critic 호출 (Tab3 사용)
call_critic() {
    local section_id="$1"
    local win="${2:-$CRITIC_WINDOW}"
    local tab="${3:-$CRITIC_TAB}"
    local timeout="${4:-$CRITIC_TIMEOUT}"

    # 트리거 조건 확인
    local should_call
    should_call=$(should_trigger_critic "$section_id")

    if [[ "$should_call" != "true" ]]; then
        echo "INFO: Critic 호출 조건 미충족 (section: $section_id)" >&2
        return 1
    fi

    echo "INFO: Critic 호출 시작 (section: $section_id, tab: $tab)" >&2

    # Critic 프롬프트 생성
    local prompt
    prompt=$(load_critic_prompt "$section_id")

    if [[ -z "$prompt" ]]; then
        echo "ERROR: Critic 프롬프트 생성 실패" >&2
        return 1
    fi

    # ChatGPT 호출 (Tab3) - 재시도 기능 사용
    if [[ -f "$CHATGPT_SCRIPT" ]]; then
        source "$CHATGPT_SCRIPT"
        local response
        response=$(chatgpt_call --tab="$tab" --timeout="${TIMEOUT_CRITIC:-90}" --retry "$prompt")

        if [[ -n "$response" ]]; then
            echo "$response"
            # 패치 제안 저장
            save_critic_response "$section_id" "$response"
        else
            echo "ERROR: ChatGPT 응답 없음 (재시도 후에도 실패)" >&2
            return 1
        fi
    else
        echo "ERROR: chatgpt.sh not found - ChatGPT connection required" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 패치 관리
# ══════════════════════════════════════════════════════════════

# Critic 응답 저장
save_critic_response() {
    local section_id="$1"
    local response="$2"

    mkdir -p "$PATCHES_DIR"

    # JSON 추출
    local json_str
    json_str=$(extract_json_from_response "$response")

    if [[ -z "$json_str" ]]; then
        echo "WARNING: Critic 응답에서 JSON 추출 실패" >&2
        return 1
    fi

    # 타임스탬프 추가
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json

data = json.loads('''$json_str''')
data['section'] = '$section_id'
data['created_at'] = '$timestamp'
data['status'] = 'pending'

# 기존 패치 파일 로드 또는 새로 생성
try:
    with open('$PENDING_PATCHES_FILE', 'r') as f:
        all_patches = json.load(f)
except:
    all_patches = {'patches': []}

all_patches['patches'].append(data)
all_patches['updated_at'] = '$timestamp'

with open('$PENDING_PATCHES_FILE', 'w') as f:
    json.dump(all_patches, f, indent=2, ensure_ascii=False)

print('Saved critic response for section: $section_id')
"
}

# 대기 중인 패치 목록 조회
list_pending_patches() {
    if [[ ! -f "$PENDING_PATCHES_FILE" ]]; then
        echo "[]"
        return
    fi

    python3 -c "
import json
with open('$PENDING_PATCHES_FILE', 'r') as f:
    data = json.load(f)
pending = [p for p in data.get('patches', []) if p.get('status') == 'pending']
print(json.dumps(pending, indent=2, ensure_ascii=False))
"
}

# 패치 상태 업데이트
update_patch_status() {
    local patch_id="$1"
    local new_status="$2"  # applied, rejected, merged

    if [[ ! -f "$PENDING_PATCHES_FILE" ]]; then
        echo "ERROR: No pending patches file" >&2
        return 1
    fi

    python3 -c "
import json
from datetime import datetime

with open('$PENDING_PATCHES_FILE', 'r') as f:
    data = json.load(f)

found = False
for p in data.get('patches', []):
    for patch in p.get('patches', []):
        if patch.get('patch_id') == '$patch_id':
            patch['status'] = '$new_status'
            patch['updated_at'] = datetime.now().isoformat()
            found = True
            break

if found:
    with open('$PENDING_PATCHES_FILE', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print('Updated patch $patch_id to status: $new_status')
else:
    print('Patch not found: $patch_id')
"
}

# ══════════════════════════════════════════════════════════════
# 변경 이력 기록
# ══════════════════════════════════════════════════════════════

# 변경 이력 추가
log_prompt_change() {
    local prompt_type="$1"
    local old_version="$2"
    local new_version="$3"
    local change_reason="$4"
    local patch_id="${5:-manual}"

    mkdir -p "$(dirname "$CHANGELOG_FILE")"

    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    cat >> "$CHANGELOG_FILE" <<EOF

## [$timestamp] $prompt_type v$old_version → v$new_version

- **Patch ID**: $patch_id
- **변경 사유**: $change_reason
- **적용 일시**: $timestamp

EOF

    echo "Logged change: $prompt_type v$old_version → v$new_version"
}

# ══════════════════════════════════════════════════════════════
# 통합 워크플로우
# ══════════════════════════════════════════════════════════════

# Critic 실행 워크플로우 (트리거 발생 시)
run_critic_workflow() {
    local section_id="$1"

    echo "=== Critic Workflow Started ===" >&2
    echo "Section: $section_id" >&2

    # 1. 트리거 확인
    local triggers
    triggers=$(check_all_triggers "$section_id")
    echo "Triggers: $triggers" >&2

    local should_run
    should_run=$(should_trigger_critic "$section_id")

    if [[ "$should_run" != "true" ]]; then
        echo "No triggers fired, skipping Critic" >&2
        return 0
    fi

    # 2. 개선 우선순위 결정
    local priority
    priority=$(determine_improvement_priority "$section_id")
    echo "Priority: $priority" >&2

    # 3. Critic 호출
    local response
    response=$(call_critic "$section_id")
    echo "Critic response received" >&2

    # 4. 결과 반환
    echo "$response"
}

# ══════════════════════════════════════════════════════════════
# 테스트
# ══════════════════════════════════════════════════════════════

test_prompt_critic() {
    echo "=== Prompt Critic Test ==="
    echo ""

    echo "--- Critic 프롬프트 생성 테스트 ---"
    load_critic_prompt "trigger_test" | head -50
    echo "..."
    echo ""

    echo "--- Critic 워크플로우 테스트 ---"
    run_critic_workflow "trigger_test"
    echo ""

    echo "--- 대기 중인 패치 목록 ---"
    list_pending_patches
}

# 직접 실행 시 테스트
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_prompt_critic
fi
