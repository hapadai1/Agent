Writer → Evaluator → Prompt Critic → Prompt Builder 각 단계별로, “매 회차 결과를 근거로 프롬프트를 점진 개선(버전 관리 포함)”하도록 설계한 프롬프트 개선 방안을 다시 정리한 거야.

0) 공통 설계 원칙(전 단계 공통)

프롬프트는 ‘길게’가 아니라 ‘고정 골격 + 작은 규칙’으로 개선

매 회차 프롬프트 변경은 1~2개 규칙만(원인 추적 가능)

결과물/점수 외에 결함 태그(defect_tags) 를 반드시 남겨서 “개선 근거”로 사용

새 버전은 바로 전면 적용하지 말고 Champion(안정) / Challenger(신규) 로 시험 후 승격

1) Writer(작성요청) 프롬프트 개선 설계
목표

다음 회차부터 “누락/모호/근거 부족” 같은 반복 결함이 원천 차단되게 작성 프롬프트 자체를 강화

Writer 프롬프트 구조(고정 골격)

역할/목표: 정부과제 심사위원 관점, 섹션 목표/분량

필수 포함 항목 체크리스트(누락 금지)

근거/수치/출처 규칙(최소 개수/형식)

출력 템플릿 고정(헤더, 문단, 표 위치)

Self-check 단계: 출력 직전에 체크리스트 기반 자체 점검 후 보완

Writer 프롬프트 개선 트리거(예시)

MISSING_REQUIRED_ITEM 1회라도 발생 → 체크리스트/템플릿 강화

NO_EVIDENCE_OR_CITATION 연속 발생 → “문단당 근거 1개” 규칙 추가

VAGUE_CLAIMS 빈발 → “모호 표현 금지 + 수치/사례로 치환” 규칙 추가

개선 방식(“결함 태그 → 규칙 패치” 매핑)

MISSING_REQUIRED_ITEM → “필수 항목 표/리스트”를 출력에 강제 포함

FORMAT_NONCOMPLIANCE → 출력 포맷을 더 엄격하게(섹션 헤더/표 템플릿 고정)

LOGIC_FLOW_WEAK → “문단별 논리 목적(문제→원인→해결→효과)” 라벨링 강제

DIFFERENTIATION_WEAK → “경쟁사 대비 3가지 차별점 + 근거” 항목 강제

Writer 프롬프트 출력 규격(권장)

본문 + “필수항목 체크 결과(OK/보완)” 를 마지막에 짧게 붙여서 누락을 자동 검출

2) Evaluator(점수요청) 프롬프트 개선 설계
목표

점수만 주는 평가가 아니라, 다음 회차에 바로 적용 가능한 수정 지시 + 프롬프트 개선 제안까지 구조화

Evaluator 출력은 JSON 고정 권장

total_score

scores_by_criteria (완성도/구체성/논리성/차별성/제출완성도…)

defect_tags (중복 가능)

evidence_anchors (본문의 “문제 문장/근거 부족 지점” 인용)

fix_instructions (Writer가 그대로 실행 가능한 수정 지시 5~10개)

prompt_patch_suggestions (프롬프트에 추가/수정해야 할 규칙 1~3개)

Evaluator 프롬프트 개선 포인트

평가 편향 방지: “말투/문장 미학”은 감점 최소화, 기준 충족/근거/논리/차별성 중심

“근거(출처)” 판단을 명시: 출처 없는 수치/추정은 감점으로 규칙화

결함 태그 정의를 프롬프트에 포함(태그 남발/중구난방 방지)

개선 트리거(예시)

평가 결과가 회차마다 요동(재현성 낮음) → 평가 기준 문구를 더 정량화

defect_tags가 애매(“뭔가 부족”) → 태그 정의를 더 구체화 + 예시 추가

3) Prompt Critic(프롬프트 개선 제안) 설계
목표

“이번 회차 실패 원인”을 프롬프트 수준의 결함으로 환원해서, 다음 버전에 반영할 패치를 제안

입력(반드시 포함)

현재 Writer 프롬프트(vX), Evaluator 프롬프트(vY)

이번 회차 output

Evaluator JSON(점수/태그/수정지시)

최근 K회 통계: defect_tags TOP3 + 빈도/연속 여부

출력(고정 포맷)

Root cause(프롬프트 레벨 원인) 1~3개

패치 제안 1~3개

(a) 바꿀 규칙

(b) 기대 효과

(c) 부작용/리스크(예: 과도한 길이, 문장 경직)

“이번 회차는 Writer를 고칠지 / Evaluator를 고칠지” 우선순위 권고

Critic 개선 규칙(중요)

“길이 늘리기” 제안은 최소화: 규칙 추가보다 ‘템플릿 고정/체크리스트 강화’ 우선

한 번에 최대 2개 패치만 권장(안정성)

4) Prompt Builder(새 버전 생성/적용) 설계
목표

Critic 제안을 실제 프롬프트 텍스트로 반영하여 v+1 생성, 변경 이력/근거를 남기고 테스트로 넘김

Builder 출력(고정)

new_prompt_text (v+1 전문)

diff_summary (무엇이 바뀌었는지 3줄 요약)

changelog (왜 바꿨는지, 어떤 결함 태그를 해결하려는지)

rollback_note (부작용 발생 시 되돌릴 지점)

적용 정책(Champion/Challenger)

Champion: 현재 운영 버전

Challenger: v+1

최소 3~5개 샘플(과거 회차/유사 섹션)로 평가 비교:

평균 점수 상승 + 핵심 결함 태그 감소 시 승격

아니면 폐기/수정(v+2) 또는 롤백

5) “매 회차 자동 개선” 운영 룰(추천)
언제 바꾸나(Trigger)

동일 defect_tag가 2회 연속

특정 항목 점수(예: 구체성)가 임계치 미만이 2회 연속

총점이 3회 정체(개선폭 < +1점 등)

얼마나 바꾸나(Change Budget)

Writer/Evaluator 중 한 쪽만 바꾸는 회차를 기본으로

한 번에 규칙 1~2개만 변경

무엇을 우선 바꾸나(Priority)

누락/형식(템플릿/체크리스트)

근거/출처(정량 규칙)

논리 구조(문단 역할 강제)

차별성(경쟁사 비교 포맷 강제)

6) 버전 관리 단위(필수 메타데이터)

prompt_id: writer / evaluator / critic / builder

version: v1, v2…

created_at

change_reason: 연결된 defect_tags

expected_effect: 어떤 점수 항목을 올릴지

metrics_after: 적용 후 평균점수/결함태그 빈도

