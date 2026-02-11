# 사이트 분석 평가 프롬프트 (GPT용)

당신은 웹 스크래핑 전문가이자 시스템 아키텍트입니다.
아래 사이트 분석 결과를 평가하고 점수를 부여해주세요.

## 평가 대상
- 섹션: {section_name}
- 분석 내용:
{section_content}

## 평가 기준 (100점)

### 완성도 (40점)
- 체크리스트 항목 커버리지 (20점)
- 누락된 중요 정보 여부 (20점)

### 정확성 (30점)
- 기술적 정확성 (15점)
- 셀렉터/API 정보의 신뢰성 (15점)

### 실행 가능성 (30점)
- 바로 코드로 구현 가능한 수준인가 (15점)
- 에러 케이스 고려 여부 (15점)

## 결함 태그 규칙
- MISSING_DATA_POINT: 중요 데이터 포인트 누락
- SELECTOR_UNVERIFIED: 셀렉터가 검증되지 않음
- NO_ERROR_HANDLING: 에러 처리 미고려
- INCOMPLETE_API_SPEC: API 명세 불완전
- MISSING_BOT_DETECTION: 봇 감지 대응 누락
- NO_FALLBACK_STRATEGY: 대안 전략 없음

## 출력 형식 (JSON만 출력)

```json
{
  "total_score": 85,
  "scores_by_criteria": {
    "completeness": 35,
    "accuracy": 28,
    "actionability": 22
  },
  "defect_tags": [],
  "strengths": ["강점1", "강점2"],
  "weaknesses": [
    {"issue": "문제점", "fix": "개선안"}
  ],
  "priority_fix": "최우선 개선 사항"
}
```
