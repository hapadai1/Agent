#!/bin/bash
# prompt_render.sh - YAML 정본에서 MD 프롬프트 렌더링
# 사용법: ./prompt_render.sh --source=_meta/writer_v1.yaml --output=writer/champion.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"
PROMPTS_DIR="${PROJECT_DIR}/prompts"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════

SOURCE=""
OUTPUT=""
PREVIEW=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --source=*)
            SOURCE="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT="${1#*=}"
            shift
            ;;
        --preview)
            PREVIEW=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════
# 렌더링 함수
# ══════════════════════════════════════════════════════════════

render_writer_prompt() {
    local yaml_file="$1"
    local output_file="$2"

    python3 <<PYEOF
import yaml
from datetime import datetime

yaml_file = '$yaml_file'
output_file = '$output_file' if '$output_file' else None
preview = $([[ "$PREVIEW" == "true" ]] && echo "True" || echo "False")

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

version = data.get('version', 1)
prompt_type = data.get('type', 'writer')
skeleton = data.get('skeleton', {})
patches = data.get('patches', [])

# 기본 구조 조합
lines = []

# 헤더
lines.append(f"# {prompt_type.title()} Prompt - v{version}")
lines.append(f"# Source: {yaml_file}")
lines.append(f"# Rendered: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
lines.append("")

# Role
if skeleton.get('role'):
    lines.append(skeleton['role'].strip())
    lines.append("")
    lines.append("---")
    lines.append("")

# Task Header
if skeleton.get('task_header'):
    lines.append(skeleton['task_header'].strip())
    lines.append("")

# Prior Summary Template (placeholder)
lines.append("{prior_summary_block}")
lines.append("")

# Section Template
if skeleton.get('section_template'):
    lines.append(skeleton['section_template'].strip())
    lines.append("")

# Research Template (placeholder)
lines.append("{research_block}")
lines.append("")

# Requirements
if skeleton.get('requirements'):
    lines.append(skeleton['requirements'].strip())
    lines.append("")

# Prohibitions
if skeleton.get('prohibitions'):
    lines.append(skeleton['prohibitions'].strip())
    lines.append("")

# User Input Detection
if skeleton.get('user_input_detection'):
    lines.append(skeleton['user_input_detection'].strip())
    lines.append("")

# Patches
if patches:
    lines.append("[자동 적용된 규칙]")
    for p in patches:
        rule = p.get('rule', '')
        if rule:
            lines.append(f"- {rule}")
    lines.append("")

content = '\n'.join(lines)

if preview:
    print(content)
else:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Rendered: {yaml_file} → {output_file}")
PYEOF
}

render_evaluator_prompt() {
    local yaml_file="$1"
    local output_file="$2"

    python3 <<PYEOF
import yaml
from datetime import datetime

yaml_file = '$yaml_file'
output_file = '$output_file' if '$output_file' else None
preview = $([[ "$PREVIEW" == "true" ]] && echo "True" || echo "False")

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

version = data.get('version', 1)
prompt_type = data.get('type', 'evaluator')
status = data.get('status', 'live')
skeleton = data.get('skeleton', {})

lines = []

# 헤더
lines.append(f"# Evaluator Prompt - {status.title()} (v{version})")
lines.append(f"# Source: {yaml_file}")
lines.append(f"# Rendered: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
lines.append("")

# Role
if skeleton.get('role'):
    lines.append(skeleton['role'].strip())
    lines.append("")
    lines.append("---")
    lines.append("")

# Task Header
if skeleton.get('task_header'):
    lines.append(skeleton['task_header'].strip())
    lines.append("")

# Rubric
rubric = skeleton.get('rubric', {})
if rubric:
    lines.append("**평가 기준: 정부 과제 수주에 성공한 사업계획서 수준**")
    lines.append("")

    # Content rubric
    content = rubric.get('content', {})
    if content:
        total = content.get('total', 80)
        lines.append(f"[내용 평가 ({total}점)]")
        for i, c in enumerate(content.get('criteria', []), 1):
            lines.append(f"{i}. {c['name']} ({c['max_score']}점): {c['description']}")
        lines.append("")

    # Format rubric
    fmt = rubric.get('format', {})
    if fmt:
        total = fmt.get('total', 20)
        lines.append(f"[형식 평가 ({total}점)]")
        start = len(content.get('criteria', [])) + 1
        for i, c in enumerate(fmt.get('criteria', []), start):
            lines.append(f"{i}. {c['name']} ({c['max_score']}점): {c['description']}")
        lines.append("")

# Defect Tags Instruction
if skeleton.get('defect_tags_instruction'):
    lines.append(skeleton['defect_tags_instruction'].strip())
    lines.append("")

# Output Format
if skeleton.get('output_format'):
    lines.append(skeleton['output_format'].strip())
    lines.append("")

content = '\n'.join(lines)

if preview:
    print(content)
else:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Rendered: {yaml_file} → {output_file}")
PYEOF
}

# ══════════════════════════════════════════════════════════════
# 전체 렌더링
# ══════════════════════════════════════════════════════════════

render_all() {
    echo "=== Rendering all prompts from _meta ==="
    echo ""

    local meta_dir="${PROMPTS_DIR}/_meta"
    local build_dir="${PROMPTS_DIR}/_build"

    mkdir -p "$build_dir"

    for yaml_file in "$meta_dir"/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            local basename
            basename=$(basename "$yaml_file" .yaml)
            local output_file="${build_dir}/${basename}.render.md"

            # 타입 감지
            local prompt_type
            prompt_type=$(python3 -c "import yaml; print(yaml.safe_load(open('$yaml_file')).get('type', 'unknown'))")

            case "$prompt_type" in
                writer)
                    render_writer_prompt "$yaml_file" "$output_file"
                    ;;
                evaluator|evaluator_frozen)
                    render_evaluator_prompt "$yaml_file" "$output_file"
                    ;;
                *)
                    echo "Skipping unknown type: $yaml_file ($prompt_type)"
                    ;;
            esac
        fi
    done

    echo ""
    echo "Build complete. Files in: $build_dir"
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

main() {
    if [[ -z "$SOURCE" ]]; then
        # 소스 없으면 전체 렌더링
        render_all
        exit 0
    fi

    local source_file="${PROMPTS_DIR}/${SOURCE}"

    if [[ ! -f "$source_file" ]]; then
        echo "ERROR: Source file not found: $source_file" >&2
        exit 1
    fi

    # 타입 감지
    local prompt_type
    prompt_type=$(python3 -c "import yaml; print(yaml.safe_load(open('$source_file')).get('type', 'unknown'))")

    local output_file=""
    if [[ -n "$OUTPUT" ]]; then
        output_file="${PROMPTS_DIR}/${OUTPUT}"
    fi

    case "$prompt_type" in
        writer)
            render_writer_prompt "$source_file" "$output_file"
            ;;
        evaluator|evaluator_frozen)
            render_evaluator_prompt "$source_file" "$output_file"
            ;;
        *)
            echo "ERROR: Unknown prompt type: $prompt_type" >&2
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
