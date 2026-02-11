# biz_plan 프로젝트 설정

## 1. 프로젝트 정보

| 항목 | 값 |
|------|-----|
| 구분 | 신규서비스기획 |
| 토픽 | AI기반 마이디지털정보 오남용 알림 서비스 |
| 내용 | "개인정보 및 사진/동영상 보호 AI 서비스" 구독 모델 |
| 상세 | 내가 모르는 사이에 유출되거나 노출된 개인정보(사진, 영상 포함)를 AI가 자동으로 탐지하고 알려주는 서비스 |
| 참조 | data/ai_anti_sns.md |

---

## 2. ChatGPT 설정

| 항목 | 값 |
|------|-----|
| 브라우저 | Google Chrome Canary |
| 탭 | Tab2 |
| URL | https://chatgpt.com/g/g-p-698a705a2d348191a5c43fc28fe1c8c5-plan1/ |

---

## 3. 챕터 구성 (s1_2 ~ s3_2)

| 섹션 | 이름 | 분량 |
|------|------|------|
| s1_2 | 서비스 배경 및 필요성 | A4 2p |
| s1_3 | 목표시장(고객) 현황 분석 | A4 2p |
| s2_1 | 서비스 현황 (준비 정도) | A4 1.5p |
| s2_2 | 실현 및 구체화 방안 | A4 2p |
| s3_1 | 비즈니스 모델 및 수익 구조 | A4 1.5p |
| s3_2 | 사업화 추진 전략 | A4 1.5p |

---

## 4. 템플릿 파일

| 용도 | 경로 |
|------|------|
| 샘플 파일 | `data/samples/{section}_case01.md` |
| 기본 프롬프트 | `prompts/writer/challenger.md` |
| 평가 (Stage1) | `prompts/evaluator/evaluator.md` |
| 평가 (Stage2) | `prompts/evaluator/evaluator_stage2.md` |

---

## 5. 경로 설정 (settings.sh 기준)

| 변수 | 경로 | 용도 |
|------|------|------|
| `SAMPLES_DIR` | `data/samples/` | 섹션 샘플 케이스 |
| `PROMPTS_DIR` | `prompts/` | 프롬프트 템플릿 |
| `RUNTIME_DIR` | `runtime/` | 런타임 데이터 |
| `STATE_DIR` | `runtime/state/` | 진행 상태 |
| `RUNS_DIR` | `runtime/runs/{date}/` | 실행 결과물 |
| `LOGS_DIR` | `runtime/logs/{date}/` | 로그 |

---

## 6. 실행 Flow

### Step 1: Prompt 생성 (`--step=prompt`)

**v1 (첫 버전):**
| Input | 출처 |
|-------|------|
| sample_file | `data/samples/{section}_case01.md` |
| base_template | `prompts/writer/challenger.md` |

**v2+ (개선 버전):**
| Input | 출처 |
|-------|------|
| sample_file | `data/samples/{section}_case01.md` |
| prev_prompt | `runtime/runs/{date}/challenger/{section}_v{n-1}.prompt.md` |
| prev_output | `runtime/runs/{date}/challenger/{section}_v{n-1}.out.md` |
| prev_eval | `runtime/runs/{date}/challenger/{section}_v{n-1}.eval.json` |
| prev_eval2 | `runtime/runs/{date}/challenger/{section}_v{n-1}.eval_stage2.json` |

### Step 2: Writer 실행 (`--step=writer`)

| Input | 출처 |
|-------|------|
| prompt_file | `runtime/runs/{date}/challenger/{section}_v{n}.prompt.md` |
| sample_file | `data/samples/{section}_case01.md` |
| research_block | `data/research/responses/{section}_*.md` |

### Step 3: Evaluator Stage1 (`--step=evaluator`)

| Input | 출처 |
|-------|------|
| writer_output | `runtime/runs/{date}/challenger/{section}_v{n}.out.md` |
| evaluator_template | `prompts/evaluator/evaluator.md` |

### Step 4: Evaluator Stage2 (별도 스크립트)

| Input | 출처 |
|-------|------|
| writer_output | `runtime/runs/{date}/challenger/{section}_v{n}.out.md` |
| evaluator_template | `prompts/evaluator/evaluator_stage2.md` |

---

## 7. 파일 흐름도

```
v1:
sample + base_template
  → [Step1] → prompt.md
  → [Step2] → out.md
  → [Step3] → eval.json
  → [Step4] → eval_stage2.json

v2+:
sample + prev_prompt + prev_out + prev_eval + prev_eval2
  → [Step1] → prompt.md
  → [Step2] → out.md
  → [Step3] → eval.json
  → [Step4] → eval_stage2.json
```

---

## 8. 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-02-10 | 경로 수정: settings.sh 환경변수 사용하도록 스크립트 업데이트 |
| 2026-02-10 | step_runner.sh, suite_runner.sh, rescore_stage2.sh 경로 수정 완료 |
