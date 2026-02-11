# AI 법원 경매 사업계획서 - Claude Agent

> Claude가 step_runner.sh를 실행하고, 결과를 판단하고, 다음 행동을 결정하는 Agent 모드입니다.

---

## 프로젝트 구조

```
projects/ai_court/
│
├── 📁 [정의 영역 - 정적]
│   ├── config/
│   │   ├── project.yaml     # 프로젝트 메타정보
│   │   ├── sections.yaml    # flow/step 정의
│   │   └── settings.sh      # 설정값
│   ├── prompts/             # 프롬프트 템플릿
│   ├── data/                # 입력 데이터, 샘플
│   ├── scripts/             # 실행 스크립트
│   └── lib/                 # 프로젝트 전용 라이브러리
│
└── 📁 [런타임 영역 - 동적]
    └── runtime/
        ├── state/           # 진행 상태 (current.json)
        ├── runs/{date}/     # 실행 결과물
        └── logs/            # 로그
```

---

## 핵심 규칙

| 역할 | 담당 |
|------|------|
| **Claude** | 두뇌 - 판단, 결정, 품질 검증 |
| **step_runner.sh** | 손발 - ChatGPT Tab 조작, 파일 저장 |
| **ChatGPT** | 실제 콘텐츠 작성 (Tab6: Prompt, Tab7: Writer, Tab8: Evaluator) |

---

## 실행 흐름

```
사용자: "s3_1 v1부터 시작해"
    ↓
Claude: ./run.sh --section=s3_1 --version=1 --step=prompt
    ↓
Claude: (프롬프트 파일 읽기 + 품질 확인)
    ↓
Claude: "프롬프트 OK. Writer 진행."
    ↓
Claude: ./run.sh --section=s3_1 --version=1 --step=writer
    ↓
Claude: (결과 파일 읽기 + 품질 판단)
    ↓
Claude: "7865자, 내용 OK. Evaluator 진행."
    ↓
Claude: ./run.sh --section=s3_1 --version=1 --step=evaluator
    ↓
Claude: (eval.json 읽기 + 점수 분석)
    ↓
Claude: "78점. v2로 개선 진행."
    ↓
Claude: ./run.sh --section=s3_1 --version=2 --step=prompt
    ↓
... (반복)
```

---

## Step Runner 명령어

### 기본 사용법
```bash
./run.sh --section=s3_1 --version=1 --step=prompt
./run.sh --section=s3_1 --version=1 --step=writer
./run.sh --section=s3_1 --version=1 --step=evaluator
```

### 옵션

| 옵션 | 설명 | 예시 |
|------|------|------|
| `--section` | 섹션 ID | s1_1, s1_2, s3_1... |
| `--version` | 버전 번호 | 1, 2, 3, 4, 5 |
| `--step` | 실행 단계 | prompt, writer, evaluator |
| `--retry` | 재시도 (새 채팅) | |
| `--dry-run` | 테스트 모드 | |

### 실행 순서

```
모든 버전 사이클:
  1. ./run.sh --section=s3_1 --version=1 --step=prompt     (프롬프트 생성)
  2. ./run.sh --section=s3_1 --version=1 --step=writer     (내용 작성)
  3. ./run.sh --section=s3_1 --version=1 --step=evaluator  (품질 평가)

점수 85점 미만 → v2로 반복

자동 반복:
  ./run.sh --section=s3_1 --loop  # v1~v5 자동 실행
```

---

## 버전 정책

| 항목 | 값 | 설명 |
|------|-----|------|
| **최대 버전** | v5 | 섹션당 최대 5회 반복 |
| **목표 점수** | 85점 | 이상 시 다음 섹션 이동 |

### 자동 판단 규칙

```
IF 점수 >= 85점:
    → 다음 섹션으로 이동 (묻지 않고 진행)

IF 버전 == 5 AND 점수 < 85점:
    → 현재 점수로 확정, 다음 섹션으로 이동 (묻지 않고 진행)

IF 버전 < 5 AND 점수 < 85점:
    → 다음 버전으로 프롬프트 개선 진행
```

---

## 상태 파일

### 현재 상태 확인
```bash
cat runtime/state/current.json
```

### 상태 구조
```json
{
  "section": "s3_1",
  "version": 1,
  "step": "prompt",
  "status": "completed",
  "timestamp": "2026-02-08T01:30:00",
  "files": {
    "output": "runtime/runs/2026-02-08/challenger/s3_1_v1.prompt.md"
  }
}
```

---

## 품질 판단 기준

### Writer 결과 검증
```bash
cat runtime/runs/{DATE}/challenger/{section}_v{version}.out.md
```

| 항목 | 기준 | 문제 시 행동 |
|------|------|-------------|
| 길이 | 500자 이상 | `--retry`로 재시도 |
| 내용 | 요청 주제와 일치 | 프롬프트 수정 후 재시도 |

### Evaluator 결과 검증
```bash
cat runtime/runs/{DATE}/challenger/{section}_v{version}.eval.json
```

| 항목 | 기준 | 문제 시 행동 |
|------|------|-------------|
| JSON 형식 | 유효한 JSON | `--retry`로 재시도 |
| 점수 85점 이상 | 목표 달성 | 다음 섹션 진행 |
| 점수 85점 미만 | 개선 필요 | 다음 버전 진행 |

---

## 사용자 명령어

| 명령어 | Claude 행동 |
|--------|-------------|
| "s3_1 v1부터 시작해" | Prompt v1부터 시작 |
| "계속 진행" | runtime/state/current.json 확인 후 다음 단계 |
| "v2 재시도" | 해당 버전 step을 --retry로 재실행 |
| "현재 상태" | runtime/state/current.json 출력 |
| "결과 확인" | 최신 출력 파일 읽고 요약 |

---

## 공통 모듈 참조

이 프로젝트는 Agent 루트의 공통 모듈을 사용합니다:

| 모듈 | 경로 | 용도 |
|------|------|------|
| 코어 라이브러리 | `../../lib/core/` | JSON, YAML 파싱 등 |
| ChatGPT 자동화 | `../../common/chatgpt.sh` | Tab 제어 |
| 블록 시스템 | `../../common/block/` | 에러 처리 |
