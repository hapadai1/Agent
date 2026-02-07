#!/bin/bash
# sections_loader.sh - sections.yaml 로더
# 기존 sections.sh의 하드코딩을 YAML 기반으로 대체

SECTIONS_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

# sections.yaml 경로 (PROJECT_DIR 기준)
_sections_file() {
    echo "${PROJECT_DIR}/sections.yaml"
}

# 캐시 파일 (성능 최적화)
_sections_cache() {
    echo "${PROJECT_DIR}/.cache/sections.json"
}

# ══════════════════════════════════════════════════════════════
# YAML → JSON 캐싱
# ══════════════════════════════════════════════════════════════

# 캐시 갱신 필요 여부 확인
_sections_need_refresh() {
    local yaml_file=$(_sections_file)
    local cache_file=$(_sections_cache)

    if [[ ! -f "$cache_file" ]]; then
        return 0  # 캐시 없음
    fi

    if [[ ! -f "$yaml_file" ]]; then
        return 1  # YAML 없음, 캐시 유지
    fi

    # YAML이 더 최신이면 갱신 필요
    [[ "$yaml_file" -nt "$cache_file" ]]
}

# 캐시 생성/갱신
_sections_refresh_cache() {
    local yaml_file=$(_sections_file)
    local cache_file=$(_sections_cache)

    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: sections.yaml not found: $yaml_file" >&2
        return 1
    fi

    mkdir -p "$(dirname "$cache_file")" 2>/dev/null

    python3 -c "
import yaml
import json

with open('$yaml_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

with open('$cache_file', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False)
" 2>/dev/null

    return $?
}

# 캐시 확인 및 갱신
_sections_ensure_cache() {
    if _sections_need_refresh; then
        _sections_refresh_cache || return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 섹션 조회 함수
# ══════════════════════════════════════════════════════════════

# 섹션 ID 목록 (순서대로)
# 사용법: sections_list
sections_list() {
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

sections = data.get('sections', [])
# order 기준 정렬
sections.sort(key=lambda x: x.get('order', 0))

for s in sections:
    print(s.get('id', ''))
" 2>/dev/null
}

# 섹션 이름 가져오기
# 사용법: section_get_name <section_id>
section_get_name() {
    local section_id="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        print(s.get('name', '$section_id'))
        break
" 2>/dev/null
}

# 섹션 페이지 수 가져오기
# 사용법: section_get_pages <section_id>
section_get_pages() {
    local section_id="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        print(s.get('pages', 1))
        break
" 2>/dev/null
}

# 섹션 가중치 가져오기
# 사용법: section_get_weight <section_id>
section_get_weight() {
    local section_id="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        print(s.get('weight', 5))
        break
" 2>/dev/null
}

# 섹션 리서치 타입 가져오기
# 사용법: section_get_research_type <section_id>
section_get_research_type() {
    local section_id="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        rt = s.get('research_type', '')
        if rt:
            print(rt)
        break
" 2>/dev/null
}

# 섹션 프롬프트 경로 가져오기
# 사용법: section_get_prompt <section_id> <type>
# type: writer, evaluator
section_get_prompt() {
    local section_id="$1"
    local prompt_type="${2:-writer}"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        prompts = s.get('prompts', {})
        print(prompts.get('$prompt_type', ''))
        break
" 2>/dev/null
}

# 섹션 체크리스트 가져오기
# 사용법: section_get_checklist <section_id>
section_get_checklist() {
    local section_id="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        checklist = s.get('checklist', [])
        for item in checklist:
            print(f'- {item}')
        break
" 2>/dev/null
}

# 사람 입력 필요 여부
# 사용법: section_needs_human <section_id>
section_needs_human() {
    local section_id="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

for s in data.get('sections', []):
    if s.get('id') == '$section_id':
        if s.get('needs_human', False):
            print('true')
        else:
            print('false')
        break
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 전체 섹션 정보
# ══════════════════════════════════════════════════════════════

# 전체 섹션 수
sections_count() {
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

print(len(data.get('sections', [])))
" 2>/dev/null
}

# 섹션 요약 출력
sections_summary() {
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    echo "Sections Summary"
    echo "═══════════════════════════════════════════"
    echo ""

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

sections = data.get('sections', [])
sections.sort(key=lambda x: x.get('order', 0))

total_pages = 0
total_weight = 0

for s in sections:
    sid = s.get('id', '')
    name = s.get('name', '')
    pages = s.get('pages', 1)
    weight = s.get('weight', 5)
    research = '📊' if s.get('research_type') else '  '
    human = '👤' if s.get('needs_human') else '  '

    total_pages += pages
    total_weight += weight

    print(f'{research}{human} {sid:12} {pages:4.1f}p  w={weight:2}  {name}')

print()
print(f'Total: {len(sections)} sections, {total_pages:.1f} pages, weight sum={total_weight}')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 기본값 조회
# ══════════════════════════════════════════════════════════════

# 기본값 가져오기
# 사용법: sections_default <key>
sections_default() {
    local key="$1"
    _sections_ensure_cache || return 1
    local cache_file=$(_sections_cache)

    python3 -c "
import json

with open('$cache_file', 'r') as f:
    data = json.load(f)

defaults = data.get('defaults', {})
print(defaults.get('$key', ''))
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 호환성 레이어 (기존 sections.sh 대체)
# ══════════════════════════════════════════════════════════════

# 기존 함수명 호환
get_section_name() {
    section_get_name "$1"
}

get_section_pages() {
    section_get_pages "$1"
}

get_section_weight() {
    section_get_weight "$1"
}

get_research_type() {
    section_get_research_type "$1"
}

# SECTION_ORDER 배열 생성 (호환성)
_sections_init_order() {
    if [[ -z "$PROJECT_DIR" ]]; then
        return
    fi

    SECTION_ORDER=()
    while IFS= read -r section_id; do
        [[ -n "$section_id" ]] && SECTION_ORDER+=("$section_id")
    done < <(sections_list)

    export SECTION_ORDER
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Sections Loader - sections.yaml 로더"
    echo ""
    echo "사용법:"
    echo "  source sections_loader.sh"
    echo ""
    echo "함수:"
    echo "  sections_list                   섹션 ID 목록"
    echo "  sections_count                  섹션 수"
    echo "  sections_summary                섹션 요약"
    echo ""
    echo "  section_get_name <id>           섹션 이름"
    echo "  section_get_pages <id>          페이지 수"
    echo "  section_get_weight <id>         가중치"
    echo "  section_get_research_type <id>  리서치 타입"
    echo "  section_get_prompt <id> <type>  프롬프트 경로"
    echo "  section_get_checklist <id>      체크리스트"
    echo "  section_needs_human <id>        사람 입력 필요 여부"
    echo ""
    echo "  sections_default <key>          기본값 조회"
fi
