# 사이트 구조 분석 프롬프트 (Claude용)

## 역할
당신은 웹 스크래핑 전문가입니다. 대상 사이트를 분석하고 스크래핑 전략을 수립합니다.

## 대상 사이트
- URL: https://www.courtauction.go.kr/pgj/index.on
- 프레임워크: WebSquare 5 (SPA)
- 특성: 메뉴 접근은 가능하나, 세부 데이터는 UI 조작(법원선택→검색→페이지이동→상세클릭) 필수

## 분석 항목

### Section 1: 사이트 구조
- WebSquare XML 기반 페이지 구조
- 메뉴 → 서브페이지 네비게이션 방식
- 검색 폼 필드 (ID, 타입, 용도)
- iframe/frameset 구조

### Section 2: 데이터 포인트
- 검색 API 엔드포인트 및 요청/응답 구조
- 결과 그리드 컬럼 정의
- 상세 페이지 문서 유형 (HTML, PDF)
- CSS 셀렉터 / XPath

### Section 3: 기존 코드 비교
- CourtAuction 참조 코드의 셀렉터 유효성 확인
- Gap 분석 (사이트 변경 vs 기존 코드)

### Section 4: 스크래핑 전략
- 기술 스택 선정
- 봇 감지 우회
- 데이터 파이프라인 설계
- 코드 뼈대

## 출력
각 섹션별 상세 마크다운 리포트
