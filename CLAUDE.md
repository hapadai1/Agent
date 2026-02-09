# Agent 프로젝트 규칙

## 디렉토리 구조

```
Agent/
├── lib/core/           # 공통 코어 라이브러리
├── common/             # 공통 도구 (ChatGPT, Claude 자동화)
├── scaffold/           # 프로젝트 생성 도구
│   └── create-project.sh
├── projects/           # 프로젝트들
│   └── {project_name}/
│       ├── config/     # 정의 (정적)
│       ├── prompts/
│       ├── data/
│       ├── scripts/
│       └── runtime/    # 런타임 (동적)
└── claude/             # (레거시) 기존 프로젝트
```

---

## 새 프로젝트 생성

```bash
./scaffold/create-project.sh
```

대화형으로 프로젝트 이름, 설명, Step을 정의하면 `projects/{name}/` 폴더가 생성됩니다.

---

## 프로젝트별 규칙 파일

각 프로젝트 폴더에 `CLAUDE.md` 파일이 있으면 해당 규칙을 우선 적용합니다.

### 활성 프로젝트

| 프로젝트 | 위치 | 트리거 명령어 |
|----------|------|---------------|
| AI 법원 경매 사업계획서 | `projects/ai_court/` | "사업계획서 계속", "계속 진행" |
| (레거시) AI 법원 경매 | `claude/ai_court/` | 기존 스크립트 실행용 |

---

## 사업계획서 프로젝트 진행 시

"사업계획서", "계속 진행", "계속해" 명령 시:

1. `projects/ai_court/CLAUDE.md` 읽기
2. `projects/ai_court/runtime/state/current.json` 읽기
3. 해당 규칙대로 진행

**직접 작성 금지** - 반드시 ChatGPT를 통해 작성

---

## 공통 모듈

| 모듈 | 경로 | 용도 |
|------|------|------|
| 코어 라이브러리 | `lib/core/` | JSON, YAML, 검증 등 |
| ChatGPT 자동화 | `common/chatgpt.sh` | Tab 제어 |
| Claude 자동화 | `common/claude.sh` | API 연동 |
| 블록 시스템 | `common/block/` | 에러 처리, 응답 래핑 |
