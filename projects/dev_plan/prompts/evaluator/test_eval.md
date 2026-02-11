# 테스트 평가 프롬프트 (GPT용)
# 변수: {test_result}, {code_content}, {design_doc}

## 역할

{role_description}

## 테스트 결과

{test_result}

## 구현 코드

{code_content}

## 원본 설계 문서

{design_doc}

## 평가 기준

{evaluation_criteria}

## 출력 형식 (JSON)

```json
{
  "test_pass": false,
  "code_quality": 0,
  "improvements": [],
  "summary": ""
}
```

## 채점 규칙

{scoring_rules}
