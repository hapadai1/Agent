#!/bin/bash
# builder.sh - 프롬프트 빌더 (범용화)
# 프롬프트 새 버전 생성 및 패치 적용
# 기존 projects/*/lib/prompt/prompt_builder.sh를 범용화

PROMPT_BUILDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 의존성
source "${PROMPT_BUILDER_DIR}/loader.sh"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════

_builder_versions_dir() {
    echo "${PROJECT_DIR}/prompts/versions"
}

_builder_patches_dir() {
    echo "${PROJECT_DIR}/prompts/patches"
}

_builder_changelog_file() {
    echo "${PROJECT_DIR}/logs/prompt_changelog.md"
}

# ══════════════════════════════════════════════════════════════
# 버전 관리
# ══════════════════════════════════════════════════════════════

# 다음 버전 번호 계산
prompt_next_version() {
    local prompt_type="$1"  # writer, evaluator

    local current_version
    if [[ "$prompt_type" == "writer" ]]; then
        current_version=$(get_active_writer_version)
    else
        current_version=$(get_active_evaluator_version)
    fi

    local version_num
    version_num=$(echo "$current_version" | sed 's/v//')
    local next_num=$((version_num + 1))

    echo "v${next_num}"
}

# ══════════════════════════════════════════════════════════════
# 패치 적용
# ══════════════════════════════════════════════════════════════

# Writer에 패치 적용하여 새 버전 생성
prompt_apply_patch() {
    local patch_json="$1"
    local prompt_type="${2:-writer}"
    local current_version="${3:-$(get_active_writer_version)}"

    local versions_dir=$(_builder_versions_dir)
    local next_version
    next_version=$(prompt_next_version "$prompt_type")

    local current_file="${versions_dir}/${prompt_type}_${current_version}.yaml"
    local new_file="${versions_dir}/${prompt_type}_${next_version}.yaml"

    if [[ ! -f "$current_file" ]]; then
        echo "ERROR: Current file not found: $current_file" >&2
        return 1
    fi

    # Python으로 YAML 수정
    python3 <<PYEOF
import yaml
import json
from datetime import datetime

with open('$current_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

patch = json.loads('''$patch_json''')

# 버전 정보 업데이트
data['version'] = int('$next_version'.replace('v', ''))
data['status'] = 'challenger'
data['created_at'] = datetime.now().strftime('%Y-%m-%d')
data['change_reason'] = patch.get('expected_effect', 'Patch applied')
data['parent_version'] = '$current_version'

# 패치 적용
action = patch.get('action', '')
rule = patch.get('rule', '')

if action == 'add_rule':
    if 'patches' not in data:
        data['patches'] = []
    data['patches'].append({
        'patch_id': patch.get('patch_id', ''),
        'rule': rule,
        'applied_at': datetime.now().isoformat()
    })

elif action == 'add_checklist_item':
    checklist = data.get('skeleton', {}).get('checklist', [])
    checklist.append(rule)
    data['skeleton']['checklist'] = checklist

elif action == 'strengthen_template':
    current_prohib = data.get('skeleton', {}).get('prohibitions', '')
    data['skeleton']['prohibitions'] = current_prohib.rstrip() + '\\n- ' + rule

# 메트릭 초기화
data['metrics'] = {
    'avg_score': 0,
    'sample_count': 0,
    'defect_frequency': {},
    'last_evaluated': None
}

with open('$new_file', 'w', encoding='utf-8') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

print(f'Created: $new_file')
PYEOF

    echo "$next_version"
}

# ══════════════════════════════════════════════════════════════
# Builder 출력
# ══════════════════════════════════════════════════════════════

# Builder 결과 생성
prompt_build_output() {
    local prompt_type="$1"
    local old_version="$2"
    local new_version="$3"
    local patch_json="$4"

    python3 -c "
import json
from datetime import datetime

patch = json.loads('''$patch_json''')

output = {
    'prompt_type': '$prompt_type',
    'old_version': '$old_version',
    'new_version': '$new_version',
    'diff_summary': f\"Patch: {patch.get('action', 'unknown')} - {patch.get('rule', '')[:50]}...\",
    'changelog': {
        'patch_id': patch.get('patch_id', ''),
        'change_reason': patch.get('expected_effect', ''),
        'applied_at': datetime.now().isoformat()
    },
    'status': 'challenger'
}

print(json.dumps(output, ensure_ascii=False, indent=2))
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# Challenger 관리
# ══════════════════════════════════════════════════════════════

# Challenger로 등록
prompt_register_challenger() {
    local prompt_type="$1"
    local new_version="$2"

    update_active_version "$prompt_type" "challenger" "$new_version"
    echo "Registered $prompt_type $new_version as challenger" >&2
}

# Challenger 승격 (Champion으로)
prompt_promote_challenger() {
    local prompt_type="$1"

    local challenger_version
    if [[ "$prompt_type" == "writer" ]]; then
        challenger_version=$(get_active_writer_version "challenger")
    else
        challenger_version=$(get_active_evaluator_version "challenger")
    fi

    if [[ -z "$challenger_version" || "$challenger_version" == "null" ]]; then
        echo "No challenger to promote" >&2
        return 1
    fi

    update_active_version "$prompt_type" "champion" "$challenger_version"
    update_active_version "$prompt_type" "challenger" ""

    echo "Promoted $prompt_type $challenger_version to champion" >&2
}

# Challenger 폐기
prompt_discard_challenger() {
    local prompt_type="$1"

    update_active_version "$prompt_type" "challenger" ""
    echo "Discarded $prompt_type challenger" >&2
}

# ══════════════════════════════════════════════════════════════
# 변경 이력
# ══════════════════════════════════════════════════════════════

# 변경 이력 기록
prompt_log_change() {
    local prompt_type="$1"
    local old_version="$2"
    local new_version="$3"
    local change_reason="$4"
    local patch_id="${5:-manual}"

    local changelog_file=$(_builder_changelog_file)
    mkdir -p "$(dirname "$changelog_file")"

    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    cat >> "$changelog_file" <<EOF

## [$timestamp] $prompt_type $old_version → $new_version

- **Patch ID**: $patch_id
- **Change Reason**: $change_reason

EOF

    echo "Logged: $prompt_type $old_version → $new_version" >&2
}

# ══════════════════════════════════════════════════════════════
# 통합 빌드
# ══════════════════════════════════════════════════════════════

# 패치에서 빌드
prompt_build_from_patch() {
    local patch_json="$1"
    local prompt_type="${2:-writer}"

    # 현재 버전
    local current_version
    if [[ "$prompt_type" == "writer" ]]; then
        current_version=$(get_active_writer_version)
    else
        current_version=$(get_active_evaluator_version)
    fi

    # 패치 적용
    local new_version
    new_version=$(prompt_apply_patch "$patch_json" "$prompt_type" "$current_version")

    if [[ -z "$new_version" ]]; then
        echo "ERROR: Failed to apply patch" >&2
        return 1
    fi

    # Builder 출력
    prompt_build_output "$prompt_type" "$current_version" "$new_version" "$patch_json"

    # Challenger 등록
    prompt_register_challenger "$prompt_type" "$new_version"

    # 변경 이력
    local patch_id change_reason
    patch_id=$(echo "$patch_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('patch_id', 'unknown'))" 2>/dev/null)
    change_reason=$(echo "$patch_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('expected_effect', 'Patch'))" 2>/dev/null)

    prompt_log_change "$prompt_type" "$current_version" "$new_version" "$change_reason" "$patch_id"
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Prompt Builder (Core)"
    echo ""
    echo "함수:"
    echo "  prompt_next_version <type>                  다음 버전 번호"
    echo "  prompt_apply_patch <json> [type] [version]  패치 적용"
    echo "  prompt_build_from_patch <json> [type]       패치에서 빌드"
    echo "  prompt_register_challenger <type> <version> Challenger 등록"
    echo "  prompt_promote_challenger <type>            Challenger 승격"
    echo "  prompt_discard_challenger <type>            Challenger 폐기"
    echo "  prompt_log_change <type> <old> <new> <reason> 변경 이력"
    echo ""
    echo "환경변수 필요:"
    echo "  PROJECT_DIR - 프로젝트 디렉토리 경로"
fi
