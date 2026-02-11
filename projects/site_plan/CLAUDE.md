# CourtAuction 사이트 분석 - Claude Agent

> Claude가 사이트를 직접 분석하고, GPT가 분석 품질을 평가하는 Agent 모드

---

## 프로젝트 구조

```
projects/site_plan/
├── config/
│   ├── project.yaml     # 프로젝트 메타정보
│   ├── sections.yaml    # 분석 섹션 정의
│   └── settings.sh      # 설정값
├── prompts/
│   ├── analyzer/        # 분석 프롬프트 (Claude용)
│   └── evaluator/       # 평가 프롬프트 (GPT용)
├── data/
│   ├── snapshots/       # 사이트 캡처 데이터
│   └── reference/       # CourtAuction 참조 코드
├── scripts/
│   └── step_runner.sh
└── runtime/
    ├── state/current.json
    ├── runs/{date}/analysis/
    └── logs/
```

---

## 역할 분담

| 역할 | 담당 | 수행 내용 |
|------|------|----------|
| **Claude** | 분석 + 결정 | 사이트 접속, HTML 분석, 코드 비교, 전략 수립 |
| **GPT** | 판단 + 평가 | 분석 품질 평가, 점수 부여, 개선 포인트 제시 |
| **step_runner.sh** | 실행 | GPT Tab 조작, 파일 저장 |

---

## 실행 흐름

```
Section 1: 사이트 구조 분석
  Claude: WebFetch → HTML 파싱 → 구조 분석 리포트 작성
  GPT: 분석 완성도 평가 (85점 목표)

Section 2: 데이터 포인트 매핑
  Claude: 필드/셀렉터/API 매핑 분석
  GPT: 데이터 커버리지 평가

Section 3: 기존 코드 비교
  Claude: CUR_hit/CourtAuction 코드 읽기 + Gap 분석
  GPT: Gap 분석 완성도 평가

Section 4: 스크래핑 전략
  Claude: 기술 스택 + 코드 설계
  GPT: 실행 가능성 평가
```

---

## 참조 프로젝트

| 항목 | 경로 |
|------|------|
| CourtAuction 코드 | `/Users/tony/Desktop/src/CUR_hit/CourtAuction/` |
| 대상 사이트 | `https://www.courtauction.go.kr/pgj/index.on` |

---

## 사용자 명령어

| 명령어 | Claude 행동 |
|--------|-------------|
| "분석 시작" | s1_site부터 순차 진행 |
| "계속 진행" | 현재 상태에서 다음 단계 |
| "결과 확인" | 최신 분석 결과 요약 |
