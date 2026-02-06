# Agent 프로젝트 규칙

## 프로젝트별 규칙 파일

각 프로젝트 폴더에 `CLAUDE.md` 파일이 있으면 해당 규칙을 우선 적용합니다.

### 활성 프로젝트

| 프로젝트 | 규칙 파일 | 트리거 명령어 |
|----------|-----------|---------------|
| AI 법원 경매 사업계획서 | `projects/ai_court_auction/CLAUDE.md` | "사업계획서 계속", "계속 진행" |

---

## 사업계획서 프로젝트 진행 시

"사업계획서", "계속 진행", "계속해" 명령 시:

1. `projects/ai_court_auction/CLAUDE.md` 읽기
2. `projects/ai_court_auction/state.json` 읽기
3. 해당 규칙대로 진행

**직접 작성 금지** - 반드시 ChatGPT를 통해 작성
