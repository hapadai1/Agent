# PlanLLM 사업계획서 - Claude Agent

> Claude가 step_runner.sh를 실행하고, 결과를 판단하고, 다음 행동을 결정하는 Agent 모드입니다.

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
# 또는: ./scripts/step_runner.sh --section=s3_1 ...
```

### 옵션

| 옵션 | 설명 | 예시 |
|------|------|------|
| `--section` | 섹션 ID | s1_1, s1_2, s3_1... |
| `--version` | 버전 번호 | 1, 2, 3, 4, 5 |
| `--step` | 실행 단계 | prompt, writer, evaluator |
| `--retry` | 재시도 (새 채팅) | |
| `--dry-run` | 테스트 모드 | |

### 실행 순서 (v1, v2, v3... 모두 동일)

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

## 탭 설정

| 탭 | 역할 | 타임아웃 | 재시도 |
|----|------|----------|--------|
| **Tab6** | 프롬프트 생성 | 900초 (15분) | 2회 |
| **Tab7** | 내용 작성 | 1500초 (25분) | 2회 |
| **Tab8** | 품질 평가 | 900초 (15분) | 2회 |

---

## 버전 정책 (중요)

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

### 섹션 이동 시 출력
```
━━━ 섹션 완료: s3_1 ━━━
최종 버전: v5
최종 점수: 65점
상태: 최대 버전 도달 (목표 미달)
→ 다음 섹션(s3_2) 진행
```

---

## 품질 판단 기준

### Prompt 결과 검증
```bash
cat runtime/runs/{DATE}/challenger/{section}_v{version}.prompt.md
```

| 항목 | 기준 | 문제 시 행동 |
|------|------|-------------|
| 길이 | 100자 이상 | `--retry`로 재시도 |
| 변수 유지 | {topic}, {section_name} 등 존재 | 수동 수정 |

### Writer 결과 검증
```bash
cat runtime/runs/{DATE}/challenger/{section}_v{version}.out.md
```

| 항목 | 기준 | 문제 시 행동 |
|------|------|-------------|
| 길이 | 500자 이상 | `--retry`로 재시도 |
| 내용 | 요청 주제와 일치 | 프롬프트 수정 후 재시도 |
| 형식 | 마크다운, 표 포함 | 프롬프트에서 규칙 추가 |

### Evaluator 결과 검증
```bash
cat runtime/runs/{DATE}/challenger/{section}_v{version}.eval.json
```

| 항목 | 기준 | 문제 시 행동 |
|------|------|-------------|
| JSON 형식 | 유효한 JSON | `--retry`로 재시도 |
| total_score | 1-100 사이 | 파싱 문제 확인 |
| 점수 85점 이상 | 목표 달성 | 다음 섹션 진행 |
| 점수 85점 미만 | 개선 필요 | 다음 버전 진행 |

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
  },
  "metrics": {
    "output_chars": 4983,
    "duration_sec": 335
  }
}
```

---

## 판단 예시

### 정상 진행
```
Prompt 결과: 2500자 ✓
→ "프롬프트 OK. Writer 진행."
→ ./run.sh --section=s3_1 --version=1 --step=writer
```

### 재시도 필요
```
Writer 결과: 3자 ✗
→ "응답이 너무 짧음. Tab 문제로 보임. 재시도."
→ ./run.sh --section=s3_1 --version=1 --step=writer --retry
```

### 버전 진행
```
Evaluator 결과: 78점
→ "목표 85점 미달. v2로 프롬프트 개선 진행."
→ ./run.sh --section=s3_1 --version=2 --step=prompt
```

### 목표 달성
```
Evaluator 결과: 87점
→ "목표 달성! 다음 섹션(s3_2)으로 진행할까요?"
```

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

## 파일 구조

```
claude/ai_court/
├── run.sh                  # 심볼릭 링크 → scripts/step_runner.sh
├── scripts/                # 실행 스크립트 모음
│   ├── step_runner.sh      # 단일/반복 step 실행
│   ├── section_runner.sh   # 전체 섹션 순차 실행
│   ├── rescore_stage2.sh   # Stage 2 재채점
│   ├── challenger.sh       # Challenger 테스트
│   └── champion.sh         # Champion 테스트
├── config/
│   ├── settings.sh         # 설정 (타임아웃, 탭 번호, 경로 등)
│   └── sections.yaml       # 섹션 정의
├── lib/
│   ├── core/               # 코어 모듈
│   └── util/               # 유틸리티 모듈
├── data/                   # 입력 데이터
│   ├── samples/            # 섹션별 샘플 (s3_1_case01.md 등)
│   └── research/           # 리서치 결과
├── runtime/                # 실행 시 생성
│   ├── runtime/state/current.json  # 현재 상태
│   ├── runs/{DATE}/challenger/  # 실행 결과
│   │   ├── s3_1_v1.prompt.md
│   │   ├── s3_1_v1.out.md
│   │   ├── s3_1_v1.eval.json
│   │   └── s3_1_v1.eval_stage2.json
│   └── logs/               # 로그 파일
├── prompts/
│   ├── writer/challenger.md
│   └── evaluator/
│       ├── evaluator.md
│       └── evaluator_stage2.md
└── docs/                   # 참고 문서
```

---

## 체크리스트

### Step 실행 전
- [ ] 이전 step 결과 확인했는가?
- [ ] 필요한 파일이 존재하는가?
- [ ] 올바른 옵션인가?

### Step 실행 후
- [ ] 결과 파일을 읽었는가?
- [ ] 품질 기준을 확인했는가?
- [ ] 다음 행동을 결정했는가?

### 문제 발생 시
- [ ] 로그 파일 확인했는가?
- [ ] --retry 옵션 시도했는가?
- [ ] 사용자에게 상황 설명했는가?
