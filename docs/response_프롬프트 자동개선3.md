지금 상황(고정 프롬프트로 반복 운영 중 + 자동 개선 프롬프트를 붙이고 싶음)에서 **가장 안전하고 재현 가능한 “권장 운영 설계”**를 다시 한 번 깔끔하게 재설계해줄게.
핵심은 같은 입력(Suite)에 대해 “고정 vs 개선”을 각각 실행하고, 평가자는 Frozen으로 고정해서 공정 비교하는 거야.

권장 운영 설계: “Snapshot 기반 Champion/Challenger + Suite 검증” (최우선 권장)
목표

고정 프롬프트(Baseline) 대비 자동 개선 프롬프트(Challenger)가 정말로 좋아졌는지

점수뿐 아니라 치명 결함(defect_tags), 안정성, 비용까지 포함해 승격 판단

1) 폴더/자산 구조(운영 전 준비물)
prompts/
  writer/
    champion.md
    challenger.md               # 새 버전은 여기로 생성
    history/
      writer_v001.md
      writer_v002.md
  evaluator/
    frozen.md                   # 비교/검증용 고정 평가자
    live.md                     # 운영용(원하면)
    history/...

suites/
  suite-5.yaml                  # 샘플 묶음 정의
  suite-holdout.yaml            # (권장) 검증용 홀드아웃
  samples/
    s1_2_case01.md
    s1_2_case02.md
    s1_3_case01.md
    ...

runs/
  2026-02-05/
    baseline/
      s1_2_case01.out.md
      s1_2_case01.eval.json
    challenger/
      ...

reports/
  2026-02-05_compare_suite-5.json
  2026-02-05_compare_suite-5.md


suites/samples/ = 고정 입력(테스트 문제지)

prompts/* = 프롬프트 버전 관리

runs/ = 실행 결과/점수 저장

reports/ = 비교 리포트(승격 판단 근거)

2) Suite 샘플(MD) 설계 원칙

각 샘플 파일은 “동일 입력으로 여러 버전 비교”가 가능하도록 입력 조건을 고정해.

샘플 MD에 들어갈 최소 요소:

섹션명 / 분량

필수 포함 항목 체크리스트

제공되는 사실/근거(있으면)

금지사항/형식(표 포함 등)

중요한 점: Baseline 결과물을 다음 입력으로 쓰지 않는다.
(그렇게 하면 “글 수정 효과”가 섞여서 프롬프트 비교가 깨짐)

3) 실험(비교) 실행 흐름 — “Suite를 두 번 돌린다”
Step A. Baseline(고정 Writer)로 Suite 전체 실행

입력: Suite 샘플들

Writer: prompts/writer/champion.md

Evaluator: prompts/evaluator/frozen.md (고정)

출력: 각 케이스 결과 + 점수 JSON 저장

Step B. Challenger(개선 Writer)로 Suite 전체 실행

입력: 동일 Suite 샘플들(완전 동일)

Writer: prompts/writer/challenger.md (또는 v+1)

Evaluator: 동일 Frozen

출력 저장

Step C. Compare(쌍체 비교)

케이스별로:

Δscore = score(challenger) - score(baseline)

defect_tags 변화(치명 태그 감소 여부)

비용/시간 증가폭

4) 승격 기준(Gate) — 점수만 보면 위험해서 “게이트”가 필수

권장 게이트(예시):

평균 총점: Challenger가 Baseline 대비 +3점 이상

치명 태그: MISSING_REQUIRED_ITEM 발생 케이스가 0개 (또는 Baseline 대비 감소)

근거 관련 태그: NO_EVIDENCE_OR_CITATION 빈도 감소

안정성(선택): 동일 케이스 3회 반복 시 점수 분산이 악화되지 않음

비용/지연: 토큰/시간 증가폭이 예: +20% 이내

이 게이트를 통과하면 Challenger → Champion 승격.

5) 자동 개선(프롬프트 진화)은 “매회차 변경”이 아니라 “트리거 기반”

운영 중에는 매회차 프롬프트를 바꾸면 흔들려.
그래서 아래처럼 나눈다:

매 회차(항상): Writer 실행 → Evaluator(Frozen 또는 Live) 평가 → 로그 적재

프롬프트 변경(가끔): 트리거가 걸릴 때만 Critic/Builder 실행

트리거 예시(권장):

동일 defect_tag 2회 연속

특정 항목 점수(예: 구체성) 임계 미만 2회 연속

총점 3회 정체

proposed_tag가 3회 반복(정식 태그 승격 검토)

6) “Tab3 프롬프트 개선 전용 탭”은 이렇게 쓰는 게 정석

Tab3는 실제로 “프롬프트 변경 작업대”야.

Tab3 입력:

현재 writer 챔피언 프롬프트

최근 K회 점수/defect 통계

대표 실패 케이스 1~2개

Evaluator가 제안한 prompt_patch_suggestions

Tab3 출력(고정 포맷 추천):

변경 규칙 1~2개만 적용한 writer_v+1

diff 요약 + 변경 이유(연결된 defect_tags)

예상 부작용(길이/경직 등)

그리고 이 writer_v+1을 prompts/writer/challenger.md로 저장한 뒤 Suite 테스트로 검증.

7) workflow.sh 연동(기존 자동 반복에 “검증/승격”만 붙이기)

기존 워크플로우에 아래 3개 커맨드만 붙이면 운영이 된다:

run_suite --writer=champion --evaluator=frozen --suite=suite-5

run_suite --writer=challenger --evaluator=frozen --suite=suite-5

compare_and_promote --gate=config/gates.yaml

compare 결과가 게이트 통과 → champion.md 교체 + history 저장 + 리포트 저장

실패 → challenger 폐기/수정(다시 Tab3)

8) 최소 실행 버전(MVP 운영) — 처음엔 이렇게만 해도 충분

Suite-5만 먼저 만든다(상/중/하 + 유사섹션 섞기)

Frozen Evaluator 1개만 둔다

승격 기준은 “평균 +3점 + 치명태그 0개” 정도로 시작

프롬프트 변경은 한 번에 1개 규칙만

결론(한 문장)

“동일 Suite 입력을 Baseline/Challenger로 각각 실행 → Frozen 평가자로 공정 비교 → 게이트 통과 시 승격”
이게 가장 운영 친화적이고, 재현/추적/안정성 모두 잡는 권장 설계야.