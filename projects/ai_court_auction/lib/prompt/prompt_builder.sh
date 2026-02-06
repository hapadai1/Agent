#!/bin/bash
# prompt_builder.sh - 프롬프트 새 버전 생성 (Builder)
# Phase 5: 프롬프트 자동개선 시스템

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# 의존성 로드
source "${SCRIPT_DIR}/prompt_loader.sh"
source "${SCRIPT_DIR}/prompt_critic.sh"

# 경로 설정
VERSIONS_DIR="${PROJECT_DIR}/prompts/versions"
PATCHES_DIR="${PROJECT_DIR}/prompts/patches"
CHANGELOG_FILE="${PROJECT_DIR}/logs/prompt_changelog.md"

# ══════════════════════════════════════════════════════════════
# 버전 관리
# ══════════════════════════════════════════════════════════════

# 다음 버전 번호 계산
get_next_version() {
    local prompt_type="$1"  # writer, evaluator

    local current_version
    if [[ "$prompt_type" == "writer" ]]; then
        current_version=$(get_active_writer_version)
    else
        current_version=$(get_active_evaluator_version)
    fi

    # v1 -> 2, v2 -> 3
    local version_num
    version_num=$(echo "$current_version" | sed 's/v//')
    local next_num=$((version_num + 1))

    echo "v${next_num}"
}

# ══════════════════════════════════════════════════════════════
# 패치 적용
# ══════════════════════════════════════════════════════════════

# 패치를 YAML에 적용하여 새 버전 생성
apply_patch_to_writer() {
    local patch_json="$1"
    local current_version="${2:-$(get_active_writer_version)}"

    local next_version
    next_version=$(get_next_version "writer")

    local current_file="${VERSIONS_DIR}/writer_${current_version}.yaml"
    local new_file="${VERSIONS_DIR}/writer_${next_version}.yaml"

    if [[ ! -f "$current_file" ]]; then
        echo "ERROR: Current writer file not found: $current_file" >&2
        return 1
    fi

    # Python으로 YAML 수정
    python3 <<PYEOF
import yaml
import json
from datetime import datetime

# 현재 버전 로드
with open('$current_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

# 패치 정보
patch = json.loads('''$patch_json''')

# 버전 정보 업데이트
data['version'] = int('$next_version'.replace('v', ''))
data['status'] = 'challenger'
data['created_at'] = datetime.now().strftime('%Y-%m-%d')
data['change_reason'] = patch.get('expected_effect', 'Critic 제안에 따른 개선')
data['parent_version'] = '$current_version'

# 패치 적용
action = patch.get('action', '')
rule = patch.get('rule', '')
location = patch.get('location', '')

if action == 'add_rule':
    # requirements에 규칙 추가
    if 'requirements' in location.lower():
        current_req = data.get('skeleton', {}).get('requirements', '')
        data['skeleton']['requirements'] = current_req.rstrip() + '\n6. ' + rule
    # 또는 patches 배열에 추가
    if 'patches' not in data:
        data['patches'] = []
    data['patches'].append({
        'patch_id': patch.get('patch_id', ''),
        'rule': rule,
        'applied_at': datetime.now().isoformat()
    })

elif action == 'add_checklist_item':
    # 체크리스트에 항목 추가
    checklist = data.get('skeleton', {}).get('checklist', [])
    checklist.append(rule)
    data['skeleton']['checklist'] = checklist
    if 'patches' not in data:
        data['patches'] = []
    data['patches'].append({
        'patch_id': patch.get('patch_id', ''),
        'rule': rule,
        'applied_at': datetime.now().isoformat()
    })

elif action == 'strengthen_template':
    # 템플릿 강화 (prohibitions에 추가)
    current_prohib = data.get('skeleton', {}).get('prohibitions', '')
    data['skeleton']['prohibitions'] = current_prohib.rstrip() + '\n- ' + rule
    if 'patches' not in data:
        data['patches'] = []
    data['patches'].append({
        'patch_id': patch.get('patch_id', ''),
        'rule': rule,
        'applied_at': datetime.now().isoformat()
    })

# 메트릭 초기화
data['metrics'] = {
    'avg_score': 0,
    'sample_count': 0,
    'defect_frequency': {},
    'last_evaluated': None
}

# 새 파일 저장
with open('$new_file', 'w', encoding='utf-8') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

print(f'Created new version: $new_file')
PYEOF

    echo "$next_version"
}

# ══════════════════════════════════════════════════════════════
# Builder 출력 생성
# ══════════════════════════════════════════════════════════════

# Builder 결과 생성 (diff, changelog, rollback)
generate_builder_output() {
    local prompt_type="$1"
    local old_version="$2"
    local new_version="$3"
    local patch_json="$4"

    python3 <<PYEOF
import json
from datetime import datetime

patch = json.loads('''$patch_json''')

output = {
    'prompt_type': '$prompt_type',
    'old_version': '$old_version',
    'new_version': '$new_version',
    'diff_summary': f"패치 적용: {patch.get('action', 'unknown')} - {patch.get('rule', '')[:50]}...",
    'changelog': {
        'patch_id': patch.get('patch_id', ''),
        'change_reason': patch.get('expected_effect', ''),
        'defect_tags_addressed': patch.get('related_tags', []) if 'related_tags' in patch else [],
        'applied_at': datetime.now().isoformat()
    },
    'rollback_note': f"문제 발생 시 {patch.get('patch_id', '')} 패치 제거 후 $old_version으로 롤백",
    'test_required': True,
    'status': 'challenger'
}

print(json.dumps(output, ensure_ascii=False, indent=2))
PYEOF
}

# ══════════════════════════════════════════════════════════════
# Challenger 등록
# ══════════════════════════════════════════════════════════════

# 새 버전을 Challenger로 등록
register_as_challenger() {
    local prompt_type="$1"
    local new_version="$2"

    update_active_version "$prompt_type" "challenger" "$new_version"
    echo "Registered $prompt_type $new_version as challenger"
}

# ══════════════════════════════════════════════════════════════
# 통합 빌드 워크플로우
# ══════════════════════════════════════════════════════════════

# Critic 응답에서 패치를 추출하여 새 버전 빌드
build_from_critic_response() {
    local critic_response="$1"
    local prompt_type="${2:-writer}"

    # JSON 추출
    local json_str
    json_str=$(extract_json_from_response "$critic_response")

    if [[ -z "$json_str" ]]; then
        echo "ERROR: Critic 응답에서 JSON 추출 실패" >&2
        return 1
    fi

    # 첫 번째 패치 추출
    local patch
    patch=$(python3 -c "
import json
data = json.loads('''$json_str''')
patches = data.get('patches', [])
if patches:
    print(json.dumps(patches[0], ensure_ascii=False))
else:
    print('')
")

    if [[ -z "$patch" ]]; then
        echo "ERROR: 패치 없음" >&2
        return 1
    fi

    # 현재 버전 가져오기
    local current_version
    if [[ "$prompt_type" == "writer" ]]; then
        current_version=$(get_active_writer_version)
    else
        current_version=$(get_active_evaluator_version)
    fi

    # 패치 적용하여 새 버전 생성
    local new_version
    if [[ "$prompt_type" == "writer" ]]; then
        new_version=$(apply_patch_to_writer "$patch" "$current_version")
    else
        echo "ERROR: Evaluator 패치는 아직 지원되지 않음" >&2
        return 1
    fi

    # Builder 출력 생성
    local output
    output=$(generate_builder_output "$prompt_type" "$current_version" "$new_version" "$patch")

    # Challenger 등록
    register_as_challenger "$prompt_type" "$new_version"

    # 변경 이력 기록
    local patch_id
    patch_id=$(echo "$patch" | python3 -c "import json,sys; print(json.load(sys.stdin).get('patch_id', 'unknown'))")
    local change_reason
    change_reason=$(echo "$patch" | python3 -c "import json,sys; print(json.load(sys.stdin).get('expected_effect', 'Critic 제안'))")

    log_prompt_change "$prompt_type" "$current_version" "$new_version" "$change_reason" "$patch_id"

    echo "$output"
}

# 대기 중인 패치에서 빌드
build_from_pending_patches() {
    local prompt_type="${1:-writer}"

    local pending
    pending=$(list_pending_patches)

    if [[ "$pending" == "[]" || -z "$pending" ]]; then
        echo "INFO: 대기 중인 패치 없음" >&2
        return 0
    fi

    # 첫 번째 pending 패치 그룹에서 첫 번째 패치 적용
    local first_patch_group
    first_patch_group=$(echo "$pending" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data:
    print(json.dumps(data[0], ensure_ascii=False))
else:
    print('')
")

    if [[ -z "$first_patch_group" ]]; then
        return 0
    fi

    # 첫 번째 패치 추출
    local first_patch
    first_patch=$(echo "$first_patch_group" | python3 -c "
import json, sys
data = json.load(sys.stdin)
patches = data.get('patches', [])
if patches:
    print(json.dumps(patches[0], ensure_ascii=False))
else:
    print('')
")

    if [[ -z "$first_patch" ]]; then
        return 0
    fi

    # 현재 버전
    local current_version
    current_version=$(get_active_writer_version)

    # 패치 적용
    local new_version
    new_version=$(apply_patch_to_writer "$first_patch" "$current_version")

    # Builder 출력
    generate_builder_output "$prompt_type" "$current_version" "$new_version" "$first_patch"

    # Challenger 등록
    register_as_challenger "$prompt_type" "$new_version"

    # 패치 상태 업데이트
    local patch_id
    patch_id=$(echo "$first_patch" | python3 -c "import json,sys; print(json.load(sys.stdin).get('patch_id', ''))")
    update_patch_status "$patch_id" "applied"

    echo "Built $prompt_type $new_version from pending patch $patch_id"
}

# ══════════════════════════════════════════════════════════════
# 롤백
# ══════════════════════════════════════════════════════════════

# Challenger를 폐기하고 Champion 유지
discard_challenger() {
    local prompt_type="$1"

    update_active_version "$prompt_type" "challenger" ""
    echo "Discarded $prompt_type challenger"
}

# ══════════════════════════════════════════════════════════════
# 테스트
# ══════════════════════════════════════════════════════════════

test_prompt_builder() {
    echo "=== Prompt Builder Test ==="
    echo ""

    echo "--- 다음 버전 번호 ---"
    echo "Writer next version: $(get_next_version writer)"
    echo ""

    echo "--- 생성된 파일 확인 ---"
    ls -la "${VERSIONS_DIR}"/writer_*.yaml
    echo ""

    echo "--- active.json 확인 ---"
    cat "${PROJECT_DIR}/prompts/active.json"
    echo ""

    echo "--- 변경 이력 확인 ---"
    tail -20 "$CHANGELOG_FILE" 2>/dev/null || echo "변경 이력 없음"
}

# 직접 실행 시 테스트
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_prompt_builder
fi
