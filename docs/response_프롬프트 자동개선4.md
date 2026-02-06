목표: “고정 프롬프트(기준선)” 대비 “자동 개선 프롬프트(새 버전)”가 진짜로 좋아졌는지, 운영 전에 공정하게 검증해서 승격(적용)할지 결정.

핵심 원칙 2개

입력은 고정(Suite 샘플): 같은 문제지로만 비교한다.

평가자는 고정(Evaluator_Frozen): 채점 기준을 고정해서 비교를 공정하게 만든다.

운영 흐름

suites/samples/에 테스트용 샘플(문제지)들을 만든다.

같은 Suite를

Baseline(고정 Writer 프롬프트) 로 한 번 돌리고 결과/점수를 저장

Challenger(개선 Writer 프롬프트) 로 또 한 번 돌리고 결과/점수를 저장

두 결과를 Evaluator_Frozen 점수 + defect_tags(결함 태그) 기준으로 비교한다.

게이트(승격 기준) 통과하면 Challenger를 Champion(운영 기본값)으로 승격한다.

예: 평균 점수 +3↑, 치명 태그 0개, 근거 부족 태그 감소, 비용/시간 증가 제한 등

자동 개선은 매번 프롬프트를 바꾸는 게 아니라

매 회차는 점수/태그 로그만 쌓고,

“같은 결함 2회 연속” 같은 트리거가 있을 때만 프롬프트를 새 버전으로 만든다.

Tab3(프롬프트 개선 전용 탭) 은

점수/태그/실패 사례를 보고 프롬프트를 v+1로 수정하는 작업대고,

수정 후에는 반드시 Suite로 다시 돌려 검증 후 승격한다.

즉, “프롬프트를 바꿨으니 좋아졌겠지”가 아니라, 고정된 문제지(Suite) + 고정된 채점자(Frozen) 로 두 버전을 반복 비교해서 통과한 버전만 운영에 반영하는 방식이야.

>> 요약설명이야.
>> 답변 :


Q1. YAML 유지 + MD 래퍼 vs 완전 MD 전환?
권장안: YAML(정본/메타+구조) + MD(렌더 결과/전송용) 분리

네 제안(“YAML은 내부 구조/패치 관리, MD는 실제 프롬프트 텍스트”)이 운영에 가장 유리해.

이유

패치/버전관리/추적: YAML이 훨씬 좋음(필드 단위 diff, 규칙 단위 patch 가능)

실제 실행: ChatGPT로 보낼 건 결국 “텍스트”라서 MD가 편함(가독성/검토/복붙)

재현성: “어떤 YAML에서 어떤 MD가 생성됐는지” 링크만 잘 남기면 회고/디버깅이 쉬움

추천 폴더 구조(조금만 확장)
prompts/
  writer/
    champion.md
    challenger.md
    history/
      writer_v001.md
      writer_v002.md
  evaluator/
    frozen.md
    live.md
    history/...

  _meta/
    writer_v001.yaml        # 정본(메타 + 구조 + 규칙)
    evaluator_v003.yaml
  _build/
    writer_v001.render.md   # YAML → 렌더 결과(자동생성)

운영 규칙(핵심만)

정본(Source of Truth): _meta/*.yaml

실행/전송 텍스트: writer/champion.md (보통 _build/*.render.md를 복사/링크)

승격 시: challenger.md → champion.md 교체 + history 저장 + 대응 YAML 버전도 함께 고정

결론: “완전 MD 전환”도 가능하지만, 자동 개선(패치)까지 생각하면 YAML 정본 + MD 렌더가 압도적으로 관리가 쉬워.

Q2. Suite 샘플 MD 포맷 템플릿(권장 구조)

네가 제시한 포맷은 거의 맞아. 다만 자동화(파서/러너)까지 고려하면 메타는 ‘YAML Front Matter’로 고정하고, 본문은 Markdown으로 쓰는 형태가 제일 깔끔해.

권장 템플릿(Front Matter + Body)
---
sample_id: s1_2_case01
section: s1_2
category: A            # A=같은 섹션, B=유사 섹션, C=단위 테스트
difficulty: mid
is_golden: false       # true면 expected_score_range 같은 절대 기준 사용
expected_score_range: [70, 85]   # is_golden=true일 때만 권장
seed_runs: 1           # 안정성 측정이면 3 권장
tags_expected:         # (선택) 이 샘플에서 특히 잡고 싶은 결함 태그
  - NO_EVIDENCE_OR_CITATION
  - MISSING_REQUIRED_ITEM
---

# 입력 조건

## 주제
AI 기반 법원 경매 분석 솔루션

## 작성 목적/독자
- 정부지원 사업계획서 심사위원 관점
- 톤: 제출용 완성 문서(코멘트/메타 발언 금지)

## 필수 포함 항목(체크리스트)
- [ ] 외부적 배경(사회·경제·기술)과 시장 기회
- [ ] 내부적 배경(대표자 경험/비전)
- [ ] 문제점 → 해결방안 연결
- [ ] 유망성/성장가능성 논증

## 제공 근거(사용 가능 팩트)
- 시장 규모: 국내 부동산 경매 시장 2조원 (2024, 대법원 통계)
- 성장률: CAGR 8.5%
- (추가 근거가 필요하면 “근거 부족”으로 표시하지 말고, 일반론으로 억지 수치 생성 금지)

## 금지사항
- 모호 표현 남발(“많은”, “상당한”, “획기적” 등) — 가능하면 수치/근거로 치환
- AI 코멘트/메타 문구(“제가 작성하겠습니다” 등)
- 출처 없는 수치 창작

## 분량/형식
- 분량: A4 1.5페이지 수준
- 표: 필요 시 1개까지 허용(선택)

왜 이 구조를 추천하냐면

러너가 --- ... --- 메타만 파싱하면 자동 분류/집계/홀드아웃 관리가 쉬움

본문은 사람이 읽고 수정하기 쉬운 MD라서 샘플 제작 속도가 빨라짐

expected_score_range는 Golden 샘플에서만 쓰는 게 좋아(전체에 넣으면 운영 부담 커짐)

네 포맷에서 보완하면 좋은 점 3개

expected_score_range는 기본값으로 넣기보다 is_golden=true인 케이스에만

“제공 근거”에 수치 창작 금지 규칙을 명확히(오염 방지)

seed_runs를 넣어두면 “점수 안정성(분산)” 테스트까지 자연스럽게 확장 가능

결론

Q1: YAML(정본) + MD(렌더/전송) 분리 운영이 최적

Q2: 네 포맷은 맞고, 운영 자동화를 위해 YAML Front Matter + MD Body 템플릿을 추천