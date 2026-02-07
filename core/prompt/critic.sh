#!/bin/bash
# critic.sh - 프롬프트 Critic (범용화)
# 프롬프트 개선 제안 및 패치 관리
# 기존 projects/*/lib/prompt/prompt_critic.sh를 범용화

PROMPT_CRITIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$PROMPT_CRITIC_DIR")"

# 의존성
source "${PROMPT_CRITIC_DIR}/loader.sh"
source "${PROMPT_CRITIC_DIR}/builder.sh"

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

# Critic 탭/타임아웃 설정
: "${CRITIC_TAB:=5}"
: "${CRITIC_TIMEOUT:=180}"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════

_critic_patches_dir() {
    echo "${PROJECT_DIR}/prompts/patches"
}

_critic_pending_file() {
    echo "${PROJECT_DIR}/prompts/patches/pending.json"
}

# ══════════════════════════════════════════════════════════════
# Critic 프롬프트 생성
# ══════════════════════════════════════════════════════════════

# Critic 프롬프트 생성
critic_generate_prompt() {
    local section_id="$1"
    local writer_version="${2:-$(get_active_writer_version)}"
    local eval_stats="${3:-}"

    # Writer 프롬프트 가져오기
    local writer_prompt
    writer_prompt=$(prompt_load_writer "$section_id" "Project Topic" "" "")

    # 섹션 정보
    local section_name
    if type section_get_name &>/dev/null; then
        section_name=$(section_get_name "$section_id" 2>/dev/null || echo "$section_id")
    else
        section_name="$section_id"
    fi

    # Critic 프롬프트 구성
    cat <<CRITIC_PROMPT
당신은 프롬프트 개선 전문가입니다.
아래 Writer 프롬프트를 분석하고 개선 패치를 제안해주세요.

═══════════════════════════════════════════════════════════════
[섹션 정보]
═══════════════════════════════════════════════════════════════
- 섹션: $section_name
- Writer 버전: $writer_version

═══════════════════════════════════════════════════════════════
[현재 Writer 프롬프트]
═══════════════════════════════════════════════════════════════
$writer_prompt

═══════════════════════════════════════════════════════════════
[평가 통계] (있는 경우)
═══════════════════════════════════════════════════════════════
$eval_stats

═══════════════════════════════════════════════════════════════
[요청사항]
═══════════════════════════════════════════════════════════════
1. 프롬프트의 약점을 분석하세요
2. 구체적인 개선 패치를 JSON 형식으로 제안하세요

출력 형식:
\`\`\`json
{
  "analysis": {
    "strengths": ["..."],
    "weaknesses": ["..."]
  },
  "patches": [
    {
      "patch_id": "PATCH_001",
      "action": "add_rule|add_checklist_item|strengthen_template",
      "rule": "추가할 규칙 내용",
      "expected_effect": "예상 효과",
      "priority": "high|medium|low"
    }
  ]
}
\`\`\`
CRITIC_PROMPT
}

# ══════════════════════════════════════════════════════════════
# Critic 호출
# ══════════════════════════════════════════════════════════════

# Critic 호출
critic_call() {
    local section_id="$1"
    local eval_stats="${2:-}"

    echo "INFO: Calling Critic for section: $section_id" >&2

    # Critic 프롬프트 생성
    local prompt
    prompt=$(critic_generate_prompt "$section_id" "" "$eval_stats")

    # LLM 호출 (llm_call 사용)
    local response
    if type llm_call &>/dev/null; then
        response=$(llm_call openai --tab="$CRITIC_TAB" --timeout="$CRITIC_TIMEOUT" --retry "$prompt")
    elif type chatgpt_call &>/dev/null; then
        response=$(chatgpt_call --tab="$CRITIC_TAB" --timeout="$CRITIC_TIMEOUT" --retry "$prompt")
    else
        echo "ERROR: No LLM caller available" >&2
        return 1
    fi

    if [[ -n "$response" ]]; then
        echo "$response"
        # 패치 저장
        critic_save_response "$section_id" "$response"
    else
        echo "ERROR: Empty response from Critic" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 패치 관리
# ══════════════════════════════════════════════════════════════

# JSON 추출
critic_extract_json() {
    local response="$1"

    python3 -c "
import re
import sys

content = '''$response'''

# JSON 블록 추출
match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    print(match.group(1).strip())
else:
    # 직접 JSON 찾기
    match = re.search(r'\{[\s\S]*\}', content)
    if match:
        print(match.group(0))
" 2>/dev/null
}

# Critic 응답 저장
critic_save_response() {
    local section_id="$1"
    local response="$2"

    local patches_dir=$(_critic_patches_dir)
    local pending_file=$(_critic_pending_file)

    mkdir -p "$patches_dir"

    # JSON 추출
    local json_str
    json_str=$(critic_extract_json "$response")

    if [[ -z "$json_str" ]]; then
        echo "WARNING: No JSON found in Critic response" >&2
        return 1
    fi

    # 타임스탬프 추가 및 저장
    python3 -c "
import json
import os
from datetime import datetime

json_str = '''$json_str'''
data = json.loads(json_str)
data['section'] = '$section_id'
data['created_at'] = datetime.now().isoformat()
data['status'] = 'pending'

pending_file = '$pending_file'

if os.path.exists(pending_file):
    try:
        with open(pending_file, 'r') as f:
            all_patches = json.load(f)
    except:
        all_patches = {'patches': []}
else:
    all_patches = {'patches': []}

all_patches['patches'].append(data)
all_patches['updated_at'] = datetime.now().isoformat()

with open(pending_file, 'w') as f:
    json.dump(all_patches, f, indent=2, ensure_ascii=False)

print(f'Saved critic response for section: $section_id')
" 2>/dev/null
}

# 대기 중인 패치 목록
critic_list_pending() {
    local pending_file=$(_critic_pending_file)

    if [[ ! -f "$pending_file" ]]; then
        echo "[]"
        return
    fi

    python3 -c "
import json
with open('$pending_file', 'r') as f:
    data = json.load(f)
pending = [p for p in data.get('patches', []) if p.get('status') == 'pending']
print(json.dumps(pending, indent=2, ensure_ascii=False))
" 2>/dev/null
}

# 패치 상태 업데이트
critic_update_patch_status() {
    local patch_id="$1"
    local new_status="$2"

    local pending_file=$(_critic_pending_file)

    if [[ ! -f "$pending_file" ]]; then
        echo "ERROR: No pending patches file" >&2
        return 1
    fi

    python3 -c "
import json
from datetime import datetime

with open('$pending_file', 'r') as f:
    data = json.load(f)

found = False
for p in data.get('patches', []):
    if p.get('status') == 'pending':
        for patch in p.get('patches', []):
            if patch.get('patch_id') == '$patch_id':
                patch['status'] = '$new_status'
                patch['updated_at'] = datetime.now().isoformat()
                found = True
                break

if found:
    with open('$pending_file', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print('Updated patch $patch_id to: $new_status')
else:
    print('Patch not found: $patch_id')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 통합 워크플로우
# ══════════════════════════════════════════════════════════════

# Critic 워크플로우 실행
critic_run_workflow() {
    local section_id="$1"
    local eval_stats="${2:-}"
    local auto_apply="${3:-false}"

    echo "=== Critic Workflow ===" >&2
    echo "Section: $section_id" >&2

    # 1. Critic 호출
    local response
    response=$(critic_call "$section_id" "$eval_stats")

    if [[ -z "$response" ]]; then
        echo "ERROR: Critic call failed" >&2
        return 1
    fi

    # 2. 자동 적용 (옵션)
    if [[ "$auto_apply" == "true" ]]; then
        echo "Auto-applying first patch..." >&2

        local json_str
        json_str=$(critic_extract_json "$response")

        local first_patch
        first_patch=$(python3 -c "
import json
data = json.loads('''$json_str''')
patches = data.get('patches', [])
if patches:
    print(json.dumps(patches[0], ensure_ascii=False))
" 2>/dev/null)

        if [[ -n "$first_patch" ]]; then
            prompt_build_from_patch "$first_patch" "writer"
        fi
    fi

    echo "$response"
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Prompt Critic (Core)"
    echo ""
    echo "함수:"
    echo "  critic_generate_prompt <section> [version] [stats]  프롬프트 생성"
    echo "  critic_call <section> [stats]                       Critic 호출"
    echo "  critic_list_pending                                 대기 중인 패치"
    echo "  critic_update_patch_status <id> <status>            패치 상태 변경"
    echo "  critic_run_workflow <section> [stats] [auto_apply]  워크플로우"
    echo ""
    echo "환경변수:"
    echo "  PROJECT_DIR    프로젝트 디렉토리"
    echo "  CRITIC_TAB     Critic 탭 번호 (기본: 5)"
    echo "  CRITIC_TIMEOUT 타임아웃 초 (기본: 180)"
fi
