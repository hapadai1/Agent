#!/bin/bash
# generator.sh - 프로젝트 생성 함수

generate_project() {
    local project_name="$1"
    local display_name="$2"
    local description="$3"
    shift 3
    local sections=("$@")

    local project_dir="${PROJECTS_DIR}/${project_name}"
    local base_dir="${SCRIPT_DIR}/base"
    local created_date
    created_date=$(date +%Y-%m-%d)

    # 1. 폴더 구조 생성
    mkdir -p "${project_dir}"/{config,prompts/{writer,evaluator},data/{samples,research},scripts,lib/util,runtime/{state,runs,logs},docs}

    # 2. project.yaml 생성
    cat > "${project_dir}/config/project.yaml" << EOF
# project.yaml - 프로젝트 메타정보

name: "${project_name}"
display_name: "${display_name}"
description: "${description}"
created: "${created_date}"
version: "1.0.0"

type: "custom"
category: "general"

runner:
  timeout_writer: 1500
  timeout_evaluator: 1500
  max_retries: 2
  max_versions: 5
  target_score: 85

dependencies:
  - "lib/core"
  - "common/chatgpt.sh"
  - "common/block"

logging:
  level: "INFO"
EOF

    # 3. sections.yaml 생성
    {
        cat << EOF
# sections.yaml - Flow/Step 정의

meta:
  project: ${project_name}
  version: 1
  description: "${description}"

sections:
EOF

        local order=100
        local idx=1
        for section in "${sections[@]}"; do
            local section_id="s${idx}"
            cat << EOF
  - id: ${section_id}
    name: "${section}"
    order: ${order}
    target: "A4 1p"
    pages: 1.0
    weight: 10
    prompts:
      writer: "writer/default.md"
      evaluator: "evaluator/default.md"

EOF
            ((idx++))
            ((order += 10))
        done
    } > "${project_dir}/config/sections.yaml"

    # 4. settings.sh 생성
    cat > "${project_dir}/config/settings.sh" << 'EOF'
#!/bin/bash
# settings.sh - 프로젝트 설정

export PROJECT_NAME="__PROJECT_NAME__"
export PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export AGENT_ROOT="$(dirname "$(dirname "$PROJECT_DIR")")"
export COMMON_DIR="${AGENT_ROOT}/common"
export LIB_CORE_DIR="${AGENT_ROOT}/lib/core"

# 타임아웃
export TIMEOUT_WRITER="${TIMEOUT_WRITER:-1500}"
export TIMEOUT_EVALUATOR="${TIMEOUT_EVALUATOR:-1500}"

# 버전 정책
export MAX_VERSION="${MAX_VERSION:-5}"
export TARGET_SCORE="${TARGET_SCORE:-85}"

# 경로 (정의 영역)
export CONFIG_DIR="${PROJECT_DIR}/config"
export DATA_DIR="${PROJECT_DIR}/data"
export PROMPTS_DIR="${PROJECT_DIR}/prompts"
export SCRIPTS_DIR="${PROJECT_DIR}/scripts"

# 경로 (런타임 영역)
export RUNTIME_DIR="${PROJECT_DIR}/runtime"
export STATE_DIR="${RUNTIME_DIR}/state"
export RUNS_DIR="${RUNTIME_DIR}/runs"
export LOGS_DIR="${RUNTIME_DIR}/logs"

export LOG_LEVEL="${LOG_LEVEL:-INFO}"

load_chatgpt() {
    local script="${COMMON_DIR}/chatgpt.sh"
    [[ -f "$script" ]] && source "$script"
}

load_core() {
    local module="$1"
    local script="${LIB_CORE_DIR}/${module}.sh"
    [[ -f "$script" ]] && source "$script"
}
EOF
    # 프로젝트 이름 치환
    sed -i '' "s/__PROJECT_NAME__/${project_name}/g" "${project_dir}/config/settings.sh"

    # 5. CLAUDE.md 생성
    cat > "${project_dir}/CLAUDE.md" << EOF
# ${display_name} - Claude Agent

> ${description}

---

## 프로젝트 구조

\`\`\`
projects/${project_name}/
├── config/           # 설정 (정적)
│   ├── project.yaml
│   ├── sections.yaml
│   └── settings.sh
├── prompts/          # 프롬프트 템플릿
├── data/             # 입력 데이터
├── scripts/          # 실행 스크립트
├── lib/              # 프로젝트 라이브러리
└── runtime/          # 런타임 데이터 (동적)
    ├── state/
    ├── runs/
    └── logs/
\`\`\`

---

## Flow

$(for i in "${!sections[@]}"; do
    echo "$(($i + 1)). ${sections[$i]}"
done)

---

## 사용법

\`\`\`bash
# Step 실행
./run.sh --section=s1 --version=1 --step=writer

# 상태 확인
cat runtime/state/current.json
\`\`\`

---

## 공통 모듈

| 모듈 | 경로 | 용도 |
|------|------|------|
| 코어 라이브러리 | \`../../lib/core/\` | JSON, YAML 파싱 |
| ChatGPT 자동화 | \`../../common/chatgpt.sh\` | Tab 제어 |
EOF

    # 6. .gitkeep 파일 생성
    touch "${project_dir}/prompts/writer/.gitkeep"
    touch "${project_dir}/prompts/evaluator/.gitkeep"
    touch "${project_dir}/data/samples/.gitkeep"
    touch "${project_dir}/data/research/.gitkeep"
    touch "${project_dir}/scripts/.gitkeep"
    touch "${project_dir}/lib/util/.gitkeep"
    touch "${project_dir}/runtime/state/.gitkeep"
    touch "${project_dir}/runtime/runs/.gitkeep"
    touch "${project_dir}/runtime/logs/.gitkeep"
    touch "${project_dir}/docs/.gitkeep"

    # 7. 기본 프롬프트 템플릿
    cat > "${project_dir}/prompts/writer/default.md" << 'EOF'
# Writer 프롬프트 템플릿

## 역할
당신은 전문 작성자입니다.

## 지시사항
{instructions}

## 출력 형식
- 마크다운 형식
- 명확한 구조화
EOF

    cat > "${project_dir}/prompts/evaluator/default.md" << 'EOF'
# Evaluator 프롬프트 템플릿

## 역할
당신은 품질 평가자입니다.

## 평가 기준
1. 완성도 (0-25점)
2. 정확성 (0-25점)
3. 구조화 (0-25점)
4. 명확성 (0-25점)

## 출력 형식 (JSON)
```json
{
  "total_score": 0,
  "details": {
    "completeness": 0,
    "accuracy": 0,
    "structure": 0,
    "clarity": 0
  },
  "feedback": "피드백 내용"
}
```
EOF

    return 0
}
