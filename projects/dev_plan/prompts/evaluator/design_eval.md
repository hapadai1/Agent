# 설계 평가 프롬프트 (Claude API용)
# 변수: {design_content}, {feature_request}

## 역할

{role_description}

## 평가 대상 설계 문서

{design_content}

## 원본 기능 요구사항

{feature_request}

## 평가 기준

{evaluation_criteria}

## 출력 형식 (JSON)

```json
{
  "score": 0,
  "pass": false,
  "strengths": [],
  "weaknesses": [],
  "questions": [],
  "improvements": []
}
```

## 채점 규칙

{scoring_rules}
