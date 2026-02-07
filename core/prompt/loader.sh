#!/bin/bash
# loader.sh - 프롬프트 로더 (범용화)
# YAML 프롬프트 파일을 로드하여 프롬프트 문자열 생성
# 기존 projects/*/lib/prompt/prompt_loader.sh를 범용화

PROMPT_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$PROMPT_LOADER_DIR")"

# ══════════════════════════════════════════════════════════════
# 경로 설정 (PROJECT_DIR 기반)
# ══════════════════════════════════════════════════════════════

_prompt_prompts_dir() {
    echo "${PROJECT_DIR}/prompts"
}

_prompt_versions_dir() {
    echo "${PROJECT_DIR}/prompts/versions"
}

_prompt_active_file() {
    echo "${PROJECT_DIR}/prompts/active.json"
}

# ══════════════════════════════════════════════════════════════
# YAML 파싱 유틸리티
# ══════════════════════════════════════════════════════════════

# YAML에서 단일 값 추출
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
    local mode="${1:-champion}"
    local active_file=$(_prompt_active_file)

    if [[ ! -f "$active_file" ]]; then
        echo "v1"
        return
    fi

    python3 -c "
import json
with open('$active_file', 'r') as f:
    data = json.load(f)
v = data.get('writer', {}).get('$mode')
print(v if v else 'v1')
" 2>/dev/null || echo "v1"
}

# 현재 활성 Evaluator 버전 가져오기
get_active_evaluator_version() {
    local mode="${1:-live}"
    local active_file=$(_prompt_active_file)

    if [[ ! -f "$active_file" ]]; then
        echo "v1"
        return
    fi

    python3 -c "
import json
with open('$active_file', 'r') as f:
    data = json.load(f)
v = data.get('evaluator', {}).get('$mode')
print(v if v else 'v1')
" 2>/dev/null || echo "v1"
}

# 활성 버전 업데이트
update_active_version() {
    local prompt_type="$1"
    local role="$2"
    local version="$3"
    local active_file=$(_prompt_active_file)

    mkdir -p "$(dirname "$active_file")"

    python3 -c "
import json
import os
from datetime import datetime

active_file = '$active_file'

if os.path.exists(active_file):
    with open(active_file, 'r') as f:
        data = json.load(f)
else:
    data = {}

if '$prompt_type' not in data:
    data['$prompt_type'] = {}

data['$prompt_type']['$role'] = '$version'
data['updated_at'] = datetime.now().isoformat()

with open(active_file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print('Updated $prompt_type.$role to $version')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 프롬프트 로드
# ══════════════════════════════════════════════════════════════

# Writer 프롬프트 로드
# 사용법: prompt_load_writer <section_id> <topic> [prior_summary] [research_data] [version]
prompt_load_writer() {
    local section_id="$1"
    local topic="$2"
    local prior_summary="${3:-}"
    local research_data="${4:-}"
    local version="${5:-$(get_active_writer_version)}"

    local versions_dir=$(_prompt_versions_dir)
    local yaml_file="${versions_dir}/writer_${version}.yaml"

    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: Writer prompt file not found: $yaml_file" >&2
        return 1
    fi

    # 섹션 정보 가져오기 (sections_loader 사용)
    local section_name pages
    if type section_get_name &>/dev/null; then
        section_name=$(section_get_name "$section_id" 2>/dev/null || echo "$section_id")
        pages=$(section_get_pages "$section_id" 2>/dev/null || echo "1")
    else
        section_name="$section_id"
        pages="1"
    fi

    # YAML에서 각 부분 로드
    local task_header section_template requirements prohibitions
    task_header=$(yaml_get_multiline "$yaml_file" "skeleton.task_header")
    task_header="${task_header//\{topic\}/$topic}"

    section_template=$(yaml_get_multiline "$yaml_file" "skeleton.section_template")
    section_template="${section_template//\{section_name\}/$section_name}"
    section_template="${section_template//\{pages\}/$pages}"

    requirements=$(yaml_get_multiline "$yaml_file" "skeleton.requirements")
    prohibitions=$(yaml_get_multiline "$yaml_file" "skeleton.prohibitions")

    # 프롬프트 조합
    local prompt="$task_header"

    # 이전 섹션 요약 (있으면)
    if [[ -n "$prior_summary" ]]; then
        local prior_template
        prior_template=$(yaml_get_multiline "$yaml_file" "skeleton.prior_summary_template")
        prior_template="${prior_template//\{prior_summary\}/$prior_summary}"
        prompt+=$'\n\n'"$prior_template"
    fi

    prompt+=$'\n\n'"$section_template"

    # 리서치 데이터 (있으면)
    if [[ -n "$research_data" ]]; then
        local research_template
        research_template=$(yaml_get_multiline "$yaml_file" "skeleton.research_template")
        research_template="${research_template//\{research_data\}/$research_data}"
        prompt+=$'\n\n'"$research_template"
    fi

    prompt+=$'\n\n'"$requirements"
    prompt+=$'\n\n'"$prohibitions"

    echo "$prompt"
}

# Evaluator 프롬프트 로드
# 사용법: prompt_load_evaluator <section_id> <content> [version] [use_frozen]
prompt_load_evaluator() {
    local section_id="$1"
    local content="$2"
    local version="${3:-$(get_active_evaluator_version)}"
    local use_frozen="${4:-false}"

    local versions_dir=$(_prompt_versions_dir)
    local yaml_file

    if [[ "$use_frozen" == "true" ]]; then
        local frozen_version
        frozen_version=$(get_active_evaluator_version "frozen_current")
        yaml_file="${versions_dir}/evaluator_frozen_${frozen_version}.yaml"
    else
        yaml_file="${versions_dir}/evaluator_${version}.yaml"
    fi

    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: Evaluator prompt file not found: $yaml_file" >&2
        return 1
    fi

    # 섹션 정보
    local section_name
    if type section_get_name &>/dev/null; then
        section_name=$(section_get_name "$section_id" 2>/dev/null || echo "$section_id")
    else
        section_name="$section_id"
    fi

    # YAML에서 각 부분 로드
    local role task_header output_format
    role=$(yaml_get_multiline "$yaml_file" "skeleton.role")

    task_header=$(yaml_get_multiline "$yaml_file" "skeleton.task_header")
    task_header="${task_header//\{section_name\}/$section_name}"
    task_header="${task_header//\{section_content\}/$content}"

    output_format=$(yaml_get_multiline "$yaml_file" "skeleton.output_format")

    # 루브릭 포맷팅
    local rubric_text
    rubric_text=$(_prompt_format_rubric "$yaml_file")

    # 프롬프트 조합
    local prompt="$role"
    prompt+=$'\n\n'"$task_header"
    prompt+=$'\n\n'"$rubric_text"
    prompt+=$'\n\n'"$output_format"

    echo "$prompt"
}

# 루브릭 포맷팅
_prompt_format_rubric() {
    local yaml_file="$1"

    python3 -c "
import yaml

with open('$yaml_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

rubric = data.get('skeleton', {}).get('rubric', {})
output = []

content = rubric.get('content', {})
if content:
    output.append(f'[내용 평가 ({content.get(\"total\", 80)}점)]')
    for i, c in enumerate(content.get('criteria', []), 1):
        output.append(f'{i}. {c[\"name\"]} ({c[\"max_score\"]}점): {c[\"description\"]}')

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
# 태그 관리
# ══════════════════════════════════════════════════════════════

# Core 태그 목록 가져오기
get_core_tags() {
    local prompts_dir=$(_prompt_prompts_dir)
    local tags_file="${prompts_dir}/tags/core_tags.yaml"

    if [[ ! -f "$tags_file" ]]; then
        echo "MISSING_REQUIRED_ITEM NO_EVIDENCE_OR_CITATION VAGUE_CLAIMS FORMAT_NONCOMPLIANCE"
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
    local prompts_dir=$(_prompt_prompts_dir)
    local tags_file="${prompts_dir}/tags/core_tags.yaml"

    if [[ ! -f "$tags_file" ]]; then
        return
    fi

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
# 호환성 레이어
# ══════════════════════════════════════════════════════════════

# 기존 함수명 호환
load_writer_prompt() {
    prompt_load_writer "$@"
}

load_evaluator_prompt() {
    prompt_load_evaluator "$@"
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Prompt Loader (Core)"
    echo ""
    echo "함수:"
    echo "  prompt_load_writer <section> <topic> [prior] [research] [version]"
    echo "  prompt_load_evaluator <section> <content> [version] [frozen]"
    echo "  get_active_writer_version [mode]"
    echo "  get_active_evaluator_version [mode]"
    echo "  update_active_version <type> <role> <version>"
    echo "  get_core_tags"
    echo ""
    echo "환경변수 필요:"
    echo "  PROJECT_DIR - 프로젝트 디렉토리 경로"
fi
