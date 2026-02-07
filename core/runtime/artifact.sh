#!/bin/bash
# artifact.sh - 실행 결과물(Artifact) 관리
# run_id별 결과물 저장, 버전 관리, 조회

ARTIFACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# Artifact 저장
# ══════════════════════════════════════════════════════════════

# Artifact 저장
# 사용법: artifact_save <type> <name> <content_or_file>
#
# type: draft, output, eval, log, prompt, config
#
# 예시:
#   artifact_save draft s1_1_v1 "$content"
#   artifact_save output final.md /path/to/file
artifact_save() {
    local type="$1"
    local name="$2"
    local content="$3"

    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "ERROR: OUTPUT_DIR not set. Run context_init first." >&2
        return 1
    fi

    local artifact_dir="${OUTPUT_DIR}/${type}"
    mkdir -p "$artifact_dir" 2>/dev/null

    local artifact_path="${artifact_dir}/${name}"

    # 파일인지 내용인지 판단
    if [[ -f "$content" ]]; then
        cp "$content" "$artifact_path"
    else
        echo "$content" > "$artifact_path"
    fi

    # 메타데이터 저장
    _artifact_log "$type" "$name" "$artifact_path"

    echo "$artifact_path"
}

# Artifact 로그 기록
_artifact_log() {
    local type="$1"
    local name="$2"
    local path="$3"

    local manifest="${OUTPUT_DIR}/.artifacts.json"

    python3 -c "
import json
import os
from datetime import datetime

manifest = '$manifest'

# 기존 데이터 로드
if os.path.exists(manifest):
    try:
        with open(manifest, 'r') as f:
            data = json.load(f)
    except:
        data = {'artifacts': []}
else:
    data = {'artifacts': []}

# 새 artifact 추가
data['artifacts'].append({
    'type': '$type',
    'name': '$name',
    'path': '$path',
    'created_at': datetime.now().isoformat(),
    'step': '${CURRENT_STEP:-unknown}'
})

data['updated_at'] = datetime.now().isoformat()

# 저장
with open(manifest, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 특정 타입 Artifact 저장
# ══════════════════════════════════════════════════════════════

# Draft 저장 (섹션별 버전 관리)
artifact_save_draft() {
    local section_id="$1"
    local content="$2"
    local version="${3:-1}"

    local name="${section_id}_v${version}.md"
    artifact_save "drafts" "$name" "$content"
}

# 평가 결과 저장
artifact_save_eval() {
    local section_id="$1"
    local eval_json="$2"
    local version="${3:-1}"

    local name="${section_id}_v${version}.json"
    artifact_save "evals" "$name" "$eval_json"
}

# 프롬프트 저장 (디버깅/재현용)
artifact_save_prompt() {
    local step_id="$1"
    local prompt="$2"

    local name="${step_id}_$(date +%H%M%S).txt"
    artifact_save "prompts" "$name" "$prompt"
}

# 로그 저장
artifact_save_log() {
    local name="$1"
    local content="$2"

    artifact_save "logs" "$name" "$content"
}

# ══════════════════════════════════════════════════════════════
# Artifact 조회
# ══════════════════════════════════════════════════════════════

# Artifact 경로 가져오기
artifact_path() {
    local type="$1"
    local name="$2"

    echo "${OUTPUT_DIR}/${type}/${name}"
}

# Artifact 내용 읽기
artifact_read() {
    local type="$1"
    local name="$2"

    local path="${OUTPUT_DIR}/${type}/${name}"

    if [[ -f "$path" ]]; then
        cat "$path"
    else
        echo "ERROR: Artifact not found: $path" >&2
        return 1
    fi
}

# 최신 Artifact 가져오기
artifact_latest() {
    local type="$1"
    local pattern="${2:-*}"

    local dir="${OUTPUT_DIR}/${type}"

    if [[ ! -d "$dir" ]]; then
        return 1
    fi

    ls -t "$dir"/$pattern 2>/dev/null | head -1
}

# 섹션별 최신 Draft 가져오기
artifact_latest_draft() {
    local section_id="$1"

    local drafts_dir="${OUTPUT_DIR}/drafts"
    if [[ ! -d "$drafts_dir" ]]; then
        return 1
    fi

    ls -t "$drafts_dir"/${section_id}_v*.md 2>/dev/null | head -1
}

# 섹션별 Draft 버전 번호 가져오기
artifact_draft_version() {
    local section_id="$1"

    local latest=$(artifact_latest_draft "$section_id")

    if [[ -n "$latest" ]]; then
        # s1_1_v3.md -> 3
        echo "$latest" | grep -oE 'v[0-9]+' | grep -oE '[0-9]+' | tail -1
    else
        echo "0"
    fi
}

# ══════════════════════════════════════════════════════════════
# Artifact 목록
# ══════════════════════════════════════════════════════════════

# 타입별 Artifact 목록
artifact_list() {
    local type="${1:-}"

    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "ERROR: OUTPUT_DIR not set" >&2
        return 1
    fi

    if [[ -n "$type" ]]; then
        local dir="${OUTPUT_DIR}/${type}"
        if [[ -d "$dir" ]]; then
            echo "[$type]"
            ls -la "$dir" 2>/dev/null | tail -n +2
        fi
    else
        # 전체 목록
        echo "Artifacts in: $OUTPUT_DIR"
        echo ""

        for dir in "$OUTPUT_DIR"/*/; do
            if [[ -d "$dir" ]]; then
                local name=$(basename "$dir")
                local count=$(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ')
                echo "  [$name] $count files"
            fi
        done
    fi
}

# Manifest 조회
artifact_manifest() {
    local manifest="${OUTPUT_DIR}/.artifacts.json"

    if [[ -f "$manifest" ]]; then
        cat "$manifest"
    else
        echo "{}"
    fi
}

# ══════════════════════════════════════════════════════════════
# Run 관리
# ══════════════════════════════════════════════════════════════

# 이전 Run 목록
artifact_list_runs() {
    local runs_dir="${PROJECT_DIR}/runs"

    if [[ ! -d "$runs_dir" ]]; then
        echo "No runs yet"
        return
    fi

    echo "Previous Runs:"
    echo ""

    for dir in "$runs_dir"/*/; do
        if [[ -d "$dir" ]]; then
            local run_id=$(basename "$dir")
            local context_file="${dir}/.context.json"
            local status="unknown"
            local started_at=""

            if [[ -f "$context_file" ]]; then
                status=$(python3 -c "import json; d=json.load(open('$context_file')); print(d.get('status','unknown'))" 2>/dev/null)
                started_at=$(python3 -c "import json; d=json.load(open('$context_file')); print(d.get('started_at','')[:19])" 2>/dev/null)
            fi

            printf "  %-20s [%s] %s\n" "$run_id" "$status" "$started_at"
        fi
    done
}

# 특정 Run 로드
artifact_load_run() {
    local run_id="$1"

    local run_dir="${PROJECT_DIR}/runs/${run_id}"

    if [[ ! -d "$run_dir" ]]; then
        echo "ERROR: Run not found: $run_id" >&2
        return 1
    fi

    export WORK_DIR="$run_dir"
    export OUTPUT_DIR="${run_dir}/outputs"
    export LOGS_DIR="${run_dir}/logs"
    export RUN_ID="$run_id"

    echo "Loaded run: $run_id" >&2
}

# ══════════════════════════════════════════════════════════════
# 정리
# ══════════════════════════════════════════════════════════════

# 오래된 Run 정리 (N일 이전)
artifact_cleanup() {
    local days="${1:-7}"
    local runs_dir="${PROJECT_DIR}/runs"

    if [[ ! -d "$runs_dir" ]]; then
        return
    fi

    echo "Cleaning up runs older than $days days..." >&2

    find "$runs_dir" -maxdepth 1 -type d -mtime "+$days" -exec rm -rf {} \; 2>/dev/null

    echo "Done" >&2
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Artifact Manager - 실행 결과물 관리"
    echo ""
    echo "저장:"
    echo "  artifact_save <type> <name> <content>"
    echo "  artifact_save_draft <section> <content> [version]"
    echo "  artifact_save_eval <section> <json> [version]"
    echo ""
    echo "조회:"
    echo "  artifact_path <type> <name>"
    echo "  artifact_read <type> <name>"
    echo "  artifact_latest <type> [pattern]"
    echo "  artifact_list [type]"
    echo ""
    echo "Run 관리:"
    echo "  artifact_list_runs"
    echo "  artifact_load_run <run_id>"
    echo "  artifact_cleanup [days]"
fi
