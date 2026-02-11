# AI 경매 분석 서비스 개발 - dev_plan

> Claude Code가 설계/개발을 주도하고, GPT/Claude API를 활용하는 소프트웨어 개발 자동화 프로젝트

---

## 프로젝트 구조

```
projects/dev_plan/
│
├── [정의 영역 - 정적]
│   ├── config/
│   │   ├── project.yaml     # 프로젝트 메타정보
│   │   └── settings.sh      # 설정값
│   ├── prompts/
│   │   ├── designer/design.md        # GPT용 설계 프롬프트
│   │   ├── developer/implement.md    # Claude용 개발 프롬프트
│   │   └── evaluator/
│   │       ├── design_eval.md        # Claude API용 설계 평가
│   │       └── test_eval.md          # GPT용 테스트 평가
│   ├── data/
│   │   ├── test/             # 테스트 데이터
│   │   └── context/          # 프로젝트 컨텍스트
│   ├── scripts/
│   │   ├── design_runner.sh  # 설계 루프 (완전 자동)
│   │   └── eval_runner.sh    # GPT 테스트 평가 (반자동)
│   ├── lib/util/             # 공통 유틸리티
│   └── docs/                 # 참고 문서
│
├── [런타임 영역 - 동적]
│   └── runtime/
│       ├── state/current.json
│       ├── runs/{date}/
│       │   ├── feature_list.md
│       │   ├── design/
│       │   │   ├── design_v1.md
│       │   │   ├── design_v1.eval.json
│       │   │   └── ...
│       │   └── dev/
│       │       ├── code_v1/
│       │       ├── test_v1.json
│       │       ├── feedback_v1.json
│       │       └── ...
│       └── logs/{date}/
│
└── run.sh                    # 진입점
```

---

## 핵심 역할

| 역할 | 담당 |
|------|------|
| **Claude Code (나)** | 두뇌 + 코드 작성 (라우팅, 코드 개발, 테스트, 재시도 판단) |
| **design_runner.sh** | 설계 루프 자동화 (GPT 작성 -> Claude API 평가, 최대 3회) |
| **eval_runner.sh** | GPT 테스트 평가 요청 (1회) |
| **ChatGPT** | 설계 문서 작성 + 테스트 결과 평가 |
| **Claude API** | 설계 문서 평가 |

---

## 실행 흐름

### Phase 0: 사용자 입력
```
사용자 -> feature_list.md 작성 -> runtime/runs/{date}/feature_list.md
```

### Phase 1: Claude Code -> 설계/개발 필요 판단

### 1-1. 설계 (완전 자동)
```
./run.sh --phase=design
  -> GPT 설계 작성 -> Claude API 평가 -> (자동 반복 최대 3회, 85점 통과)
```

### 1-2. 개발 (Claude Code 주도)
```
1. Claude Code: 승인된 설계 읽기 (runtime/runs/{date}/design/design_v{final}.md)
2. Claude Code: 코드 작성 + 테스트 실행
3. Claude Code: ./run.sh --phase=eval --version=1 (GPT 평가 요청)
4. Claude Code: feedback_v1.json 읽기 -> 재시도/종료 판단
```

---

## 명령어

### run.sh 사용법

| 명령어 | 설명 |
|--------|------|
| `./run.sh --phase=design` | 설계 자동 반복 |
| `./run.sh --phase=design --version=2` | v2부터 시작 |
| `./run.sh --phase=design --dry-run` | 설계 테스트 |
| `./run.sh --phase=eval --version=1` | v1 테스트 평가 |
| `./run.sh --status` | 현재 상태 출력 |

---

## 사용자 명령어

| 명령어 | Claude Code 행동 |
|--------|-----------------|
| "개발 시작" | feature_list 확인 -> 라우팅 |
| "설계 실행" | `./run.sh --phase=design` 실행 |
| "코드 작성" | 승인된 설계 읽기 -> 직접 개발 시작 |
| "평가 요청" | `./run.sh --phase=eval --version=N` 실행 |
| "현재 상태" | `./run.sh --status` 출력 |
| "계속 진행" | current.json 확인 후 다음 단계 |

---

## 버전 정책

### 설계 Phase

| 항목 | 값 |
|------|-----|
| 최대 버전 | 3회 |
| 목표 점수 | 85점 |
| 작성자 | ChatGPT |
| 평가자 | Claude API |

### 개발 Phase

| 항목 | 값 |
|------|-----|
| 최대 버전 | 5회 (Claude Code 판단) |
| 작성자 | Claude Code (직접) |
| 평가자 | ChatGPT |

---

## 상태 파일

```bash
cat runtime/state/current.json
```

```json
{
  "phase": "design",
  "version": 1,
  "step": "eval",
  "status": "completed",
  "timestamp": "2026-02-10T12:00:00+09:00",
  "files": {
    "output": "runtime/runs/2026-02-10/design/design_v1.eval.json"
  }
}
```

---

## 공통 모듈 참조

| 모듈 | 경로 | 용도 |
|------|------|------|
| 코어 라이브러리 | `../../lib/core/` | JSON, YAML 파싱 등 |
| ChatGPT 자동화 | `../../common/chatgpt.sh` | Tab 제어 |
| Claude 자동화 | `../../common/claude.sh` | API 연동 |

---

## 직접 작성 금지

설계 문서와 테스트 평가는 반드시 GPT/Claude API를 통해 작성. Claude Code는 코드만 직접 작성.
