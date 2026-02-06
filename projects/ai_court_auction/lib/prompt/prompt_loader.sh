#!/bin/bash
# prompt_loader.sh - YAML 프롬프트 파일을 로드하여 프롬프트 문자열 생성
# Phase 1: 프롬프트 자동개선 시스템

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"
PROMPTS_DIR="${PROJECT_DIR}/prompts"
VERSIONS_DIR="${PROMPTS_DIR}/versions"
ACTIVE_FILE="${PROMPTS_DIR}/active.json"

# ══════════════════════════════════════════════════════════════
# YAML 파싱 유틸리티
# ══════════════════════════════════════════════════════════════

# YAML에서 단일 값 추출 (Python3 사용)
yaml_get() {
    local file="$1"
    local key="$2"

    python3 -c "
import yaml
import sys

with open('$file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

keys = '$key'.split('.')
result = data
for k in keys:
    if result is None:
        break
    if isinstance(result, dict):
        result = result.get(k)
    elif isinstance(result, list) and k.isdigit():
        result = result[int(k)]
    else:
        result = None

if result is not None:
    if isinstance(result, (dict, list)):
        import json
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(result)
" 2>/dev/null
}

# YAML에서 멀티라인 값 추출
yaml_get_multiline() {
    local file="$1"
    local key="$2"

    python3 -c "
import yaml
with open('$file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
keys = '$key'.split('.')
result = data
for k in keys:
    if result is None:
        break
    if isinstance(result, dict):
        result = result.get(k)
result = result if result else ''
print(result.strip() if isinstance(result, str) else '')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 활성 버전 관리
# ══════════════════════════════════════════════════════════════

# 현재 활성 Writer 버전 가져오기
get_active_writer_version() {
    local mode="${1:-champion}"  # champion 또는 challenger

    if [[ ! -f "$ACTIVE_FILE" ]]; then
        echo "v1"
        return
    fi

    local version
    version=$(python3 -c "
import json
with open('$ACTIVE_FILE', 'r') as f:
    data = json.load(f)
v = data.get('writer', {}).get('$mode')
print(v if v else 'v1')
" 2>/dev/null)

    echo "${version:-v1}"
}

# 현재 활성 Evaluator 버전 가져오기
get_active_evaluator_version() {
    local mode="${1:-live}"  # live, frozen_current, frozen_previous

    if [[ ! -f "$ACTIVE_FILE" ]]; then
        echo "v1"
        return
    fi

    local version
    version=$(python3 -c "
import json
with open('$ACTIVE_FILE', 'r') as f:
    data = json.load(f)
v = data.get('evaluator', {}).get('$mode')
print(v if v else 'v1')
" 2>/dev/null)

    echo "${version:-v1}"
}

# ══════════════════════════════════════════════════════════════
# Writer 프롬프트 생성
# ══════════════════════════════════════════════════════════════

# Writer 프롬프트 로드 및 조합
load_writer_prompt() {
    local section_id="$1"
    local topic="$2"
    local prior_summary="$3"
    local research_data="$4"
    local version="${5:-$(get_active_writer_version)}"

    local yaml_file="${VERSIONS_DIR}/writer_${version}.yaml"

    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: Writer prompt file not found: $yaml_file" >&2
        return 1
    fi

    # 섹션 정보 가져오기 (기존 sections.sh, prompts.sh 활용)
    [[ -f "${LIB_DIR}/util/sections.sh" ]] && source "${LIB_DIR}/util/sections.sh"
    [[ -f "${SCRIPT_DIR}/prompts.sh" ]] && source "${SCRIPT_DIR}/prompts.sh"

    local section_name
    section_name=$(get_section_name "$section_id" 2>/dev/null || echo "$section_id")
    local pages
    pages=$(get_section_pages "$section_id" 2>/dev/null || echo "1")
    local section_detail
    section_detail=$(get_section_detail "$section_id" 2>/dev/null || echo "")

    # YAML에서 각 부분 로드
    local task_header
    task_header=$(yaml_get_multiline "$yaml_file" "skeleton.task_header")
    task_header="${task_header//\{topic\}/$topic}"

    local section_template
    section_template=$(yaml_get_multiline "$yaml_file" "skeleton.section_template")
    section_template="${section_template//\{section_name\}/$section_name}"
    section_template="${section_template//\{section_detail\}/$section_detail}"
    section_template="${section_template//\{pages\}/$pages}"

    local requirements
    requirements=$(yaml_get_multiline "$yaml_file" "skeleton.requirements")

    local prohibitions
    prohibitions=$(yaml_get_multiline "$yaml_file" "skeleton.prohibitions")

    local user_input_detection
    user_input_detection=$(yaml_get_multiline "$yaml_file" "skeleton.user_input_detection")

    # 프롬프트 조합
    local prompt="$task_header"

    # 이전 섹션 요약 추가 (있으면)
    if [[ -n "$prior_summary" ]]; then
        local prior_template
        prior_template=$(yaml_get_multiline "$yaml_file" "skeleton.prior_summary_template")
        prior_template="${prior_template//\{prior_summary\}/$prior_summary}"
        prompt+=$'\n\n'"$prior_template"
    fi

    prompt+=$'\n\n'"$section_template"

    # 리서치 데이터 추가 (있으면)
    if [[ -n "$research_data" ]]; then
        local research_template
        research_template=$(yaml_get_multiline "$yaml_file" "skeleton.research_template")
        research_template="${research_template//\{research_data\}/$research_data}"
        prompt+=$'\n\n'"$research_template"
    fi

    prompt+=$'\n\n'"$requirements"
    prompt+=$'\n\n'"$prohibitions"
    prompt+=$'\n\n'"$user_input_detection"

    # 동적 패치 적용 (있으면)
    local patches
    patches=$(yaml_get "$yaml_file" "patches")
    if [[ -n "$patches" && "$patches" != "[]" && "$patches" != "null" ]]; then
        prompt+=$'\n\n'"[추가 규칙 - 자동 적용]"
        prompt+=$'\n'"$patches"
    fi

    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# Evaluator 프롬프트 생성
# ══════════════════════════════════════════════════════════════

# Evaluator 프롬프트 로드 및 조합
load_evaluator_prompt() {
    local section_id="$1"
    local section_content="$2"
    local version="${3:-$(get_active_evaluator_version)}"
    local use_frozen="${4:-false}"

    # Frozen 사용 시 파일 변경
    local yaml_file
    if [[ "$use_frozen" == "true" ]]; then
        local frozen_version
        frozen_version=$(get_active_evaluator_version "frozen_current")
        yaml_file="${VERSIONS_DIR}/evaluator_frozen_${frozen_version}.yaml"
    else
        yaml_file="${VERSIONS_DIR}/evaluator_${version}.yaml"
    fi

    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: Evaluator prompt file not found: $yaml_file" >&2
        return 1
    fi

    # 섹션 정보
    [[ -f "${LIB_DIR}/util/sections.sh" ]] && source "${LIB_DIR}/util/sections.sh"
    local section_name
    section_name=$(get_section_name "$section_id" 2>/dev/null || echo "$section_id")

    # YAML에서 각 부분 로드
    local role
    role=$(yaml_get_multiline "$yaml_file" "skeleton.role")

    local task_header
    task_header=$(yaml_get_multiline "$yaml_file" "skeleton.task_header")
    task_header="${task_header//\{section_name\}/$section_name}"
    task_header="${task_header//\{section_content\}/$section_content}"

    local defect_tags_instruction
    defect_tags_instruction=$(yaml_get_multiline "$yaml_file" "skeleton.defect_tags_instruction")

    local output_format
    output_format=$(yaml_get_multiline "$yaml_file" "skeleton.output_format")

    # 루브릭 추출 및 포맷
    local rubric_text
    rubric_text=$(format_rubric "$yaml_file")

    # 프롬프트 조합
    local prompt="$role"
    prompt+=$'\n\n'"$task_header"
    prompt+=$'\n\n'"**평가 기준: 정부 과제 수주에 성공한 사업계획서 수준**"
    prompt+=$'\n\n'"$rubric_text"
    prompt+=$'\n\n'"$defect_tags_instruction"
    prompt+=$'\n\n'"$output_format"

    echo "$prompt"
}

# 루브릭 포맷팅
format_rubric() {
    local yaml_file="$1"

    python3 -c "
import yaml

with open('$yaml_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

rubric = data.get('skeleton', {}).get('rubric', {})
output = []

# 내용 평가
content = rubric.get('content', {})
if content:
    output.append(f'[내용 평가 ({content.get(\"total\", 80)}점)]')
    for i, c in enumerate(content.get('criteria', []), 1):
        output.append(f'{i}. {c[\"name\"]} ({c[\"max_score\"]}점): {c[\"description\"]}')

# 형식 평가
fmt = rubric.get('format', {})
if fmt:
    output.append('')
    output.append(f'[형식 평가 ({fmt.get(\"total\", 20)}점)]')
    for i, c in enumerate(fmt.get('criteria', []), len(content.get('criteria', [])) + 1):
        output.append(f'{i}. {c[\"name\"]} ({c[\"max_score\"]}점): {c[\"description\"]}')

print('\n'.join(output))
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# Core Tags 로드
# ══════════════════════════════════════════════════════════════

# Core 태그 목록 가져오기
get_core_tags() {
    local tags_file="${PROMPTS_DIR}/tags/core_tags.yaml"

    if [[ ! -f "$tags_file" ]]; then
        echo "MISSING_REQUIRED_ITEM NO_EVIDENCE_OR_CITATION VAGUE_CLAIMS FORMAT_NONCOMPLIANCE LOGIC_FLOW_WEAK DIFFERENTIATION_WEAK"
        return
    fi

    python3 -c "
import yaml
with open('$tags_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
tags = [t['id'] for t in data.get('tags', [])]
print(' '.join(tags))
" 2>/dev/null
}

# 태그 정의 가져오기
get_tag_definition() {
    local tag_id="$1"
    local tags_file="${PROMPTS_DIR}/tags/core_tags.yaml"

    python3 -c "
import yaml
with open('$tags_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
for t in data.get('tags', []):
    if t['id'] == '$tag_id':
        print(t.get('definition', ''))
        break
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 버전 관리 유틸리티
# ══════════════════════════════════════════════════════════════

# 활성 버전 업데이트
update_active_version() {
    local prompt_type="$1"  # writer 또는 evaluator
    local role="$2"         # champion, challenger, live, frozen_current 등
    local version="$3"

    python3 -c "
import json
from datetime import datetime

with open('$ACTIVE_FILE', 'r') as f:
    data = json.load(f)

if '$prompt_type' not in data:
    data['$prompt_type'] = {}

data['$prompt_type']['$role'] = '$version'
data['updated_at'] = datetime.now().isoformat()

with open('$ACTIVE_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print('Updated $prompt_type.$role to $version')
"
}

# Challenger 승격
promote_challenger() {
    local prompt_type="$1"  # writer 또는 evaluator

    local challenger_version
    if [[ "$prompt_type" == "writer" ]]; then
        challenger_version=$(get_active_writer_version "challenger")
        if [[ -z "$challenger_version" || "$challenger_version" == "null" ]]; then
            echo "No challenger to promote"
            return 1
        fi
        update_active_version "writer" "champion" "$challenger_version"
        update_active_version "writer" "challenger" ""
    else
        challenger_version=$(get_active_evaluator_version "live")
        # Evaluator는 Live가 새 버전이 되면 Frozen도 갱신 검토
        echo "Evaluator promotion requires manual review"
        return 1
    fi

    echo "Promoted $prompt_type challenger ($challenger_version) to champion"
}

# ══════════════════════════════════════════════════════════════
# 호환성 레이어 (기존 prompts.sh 대체)
# ══════════════════════════════════════════════════════════════

# 기존 prompt_draft() 대체
prompt_draft_v2() {
    local section_id="$1"
    local topic="$2"
    local prior_summary="$3"
    local research_data="$4"

    load_writer_prompt "$section_id" "$topic" "$prior_summary" "$research_data"
}

# 기존 prompt_verify() 대체
prompt_verify_v2() {
    local section_id="$1"
    local section_content="$2"
    local use_frozen="${3:-false}"

    load_evaluator_prompt "$section_id" "$section_content" "" "$use_frozen"
}

# ══════════════════════════════════════════════════════════════
# 테스트/디버그
# ══════════════════════════════════════════════════════════════

# 로더 테스트
test_prompt_loader() {
    echo "=== Prompt Loader Test ==="
    echo ""
    echo "Active Writer Version: $(get_active_writer_version)"
    echo "Active Evaluator Version: $(get_active_evaluator_version)"
    echo "Active Evaluator Frozen: $(get_active_evaluator_version frozen_current)"
    echo ""
    echo "Core Tags: $(get_core_tags)"
    echo ""
    echo "--- Writer Prompt (s1_2) ---"
    load_writer_prompt "s1_2" "AI 기반 법원 경매 솔루션" "" "" | head -30
    echo "..."
    echo ""
    echo "--- Evaluator Prompt (s1_2) ---"
    load_evaluator_prompt "s1_2" "[테스트 콘텐츠]" "" "false" | head -30
    echo "..."
}

# 직접 실행 시 테스트
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_prompt_loader
fi
