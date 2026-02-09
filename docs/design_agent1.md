
이 설계는 한마디로 **“문서 생성 작업을 자동으로 돌리는 실행 프레임워크(Flow 오케스트레이터)”**를 위한 거예요.
특히 당신이 말한 방식처럼 GPT가 생성하고(프롬프트/본문/평가), Claude Code가 감독·판정(JSON)해서 재실행/점프/중단을 자동 결정하는 파이프라인을 프로젝트마다 다른 Flow로 구성할 수 있게 만든 설계입니다.



설명: 무엇을 해결하려는 설계인가

1. 왜 필요한가

사업계획서 같은 “제출용 문서”는 한 번에 끝나기 어렵고,

형식 규칙(표, 소제목, 금지어, 길이, URL 금지 등)

근거 규칙([R#] 인용, 수치 문장 등)

논리 흐름/차별화(KPI, 경쟁사 비교 등)

이런 조건이 조금만 어긋나도 재작성 루프가 생깁니다.
그래서 “사람이 매번 눈으로 확인하고 다시 시키는 과정”을 자동화하려고 하는 설계예요.



2. 설계가 하는 일

**Flow(YAML)**로 “이번 프로젝트는 어떤 단계로 돌릴지”를 정의한다.

Runner가 정의된 블록을 순서대로 실행한다.

생성(GPT) 결과를 Claude Code가 JSON으로 PASS/재실행/점프/중단 판정한다.

실패 시 Claude가 준 next_instruction_for_gpt를 다음 GPT 재실행에 자동 주입해서 자동 개선 루프를 만든다.

모든 결과/판정을 run_dir에 남겨 재현/감사/디버깅이 가능하게 한다.


- 기능 리스트
1) Flow 기반 오케스트레이션

- 프로젝트별 Flow(블록 그래프) 정의 지원(순서/분기/루프)

- 블록 단위 실행 및 상태 관리(다음 단계, 재실행, 점프, 중단)

- 프로젝트마다 블록 역할(action)과 구성을 자유롭게 변경 가능


2) 블록 실행(최소 2종)

- GPT 블록: 프롬프트/본문/평가 등 “생성” 수행

- Claude 블록(Claude Code CLI): “검수/판정” 수행(출력은 JSON only)


3) Claude 판정(JSON) 기반 제어

- decision enum 4개 고정: PASS / RERUN_PREV / GOTO / STOP

- reasons/tags를 통한 결함 원인 기록

- RERUN 시 재실행 대상(target) 필수화로 모호성 제거


4) 재실행 지시 주입(자동 개선 루프)

- Claude의 next_instruction_for_gpt를 표준 파일로 저장

- GPT 템플릿의 {prior_instruction}로 자동 주입

- 결과적으로 “생성 → 판정 → 재생성” 루프를 자동화


5) 의존성/입력 참조 문법 표준화

file://... 정적 입력

${block_id.outputs.main/meta/decision} 블록 산출물 참조

${runtime.request/evidence/vars/prior_instruction} 런타임 표준 입력 참조


6) 입력 결합 규격(재현성)

- 다중 inputs를 선언 순서대로 결합

- BEGIN/END 구분자 고정으로 “어디서 온 입력인지” 모델 입력에 남김


7) 에러 처리 및 가드(운영 안정성)

- GPT: empty/timeout/min_length_fail 등 재시도 규칙

- Claude: JSON 파싱/스키마/invalid_decision 재시도 규칙

- 블록별 min_length 기본값 운영(예: content 1200 chars)


8) 루프 방지(비용 폭주 방지)

- max_iterations 기본 제한

- 동일 decision/tags 반복 시 조기 STOP(N회 연속 실패 차단)


9) 아티팩트/로그 저장(run_dir)

- 블록별 결과(main), 메타(meta), Claude decision.json 저장

- 렌더링된 최종 프롬프트/결합 입력도 저장 가능

- 재현/감사/디버깅에 필요한 실행 흔적 확보


10) 경로/스코프 안전장치

- file:// 입력은 프로젝트 루트 이하로 제한(실수/오용 방지)


11) 옵션: evaluator 최소 계약

- 평가를 넣는 프로젝트의 경우 eval.json 최소 스키마(tags/issues/score) 고정

- final_judge가 평가 결과를 일관되게 참조 가능


