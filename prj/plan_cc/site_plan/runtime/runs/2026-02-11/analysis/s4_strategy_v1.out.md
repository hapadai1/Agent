# Section 4: 스크래핑 전략 및 코드 설계

## 1. 전략 요약

### 핵심 결론
- **기존 CourtAuction 코드 대부분 유효** → 리팩토링 수준의 개선
- **검색 API 직접 호출** → 목록 스크래핑 성능 대폭 향상 가능
- **WebSquare JSON 추출** → 데이터 정확도 향상

### 사이트 특성 (중요)
```
⚠️ WebSquare SPA 사이트
  - URL 직접 접근 불가 → 메뉴 네비게이션 필수
  - 모든 데이터는 JavaScript 실행 후 DOM에 렌더링
  - 세션/쿠키 관리 필수
  - Selenium 또는 Playwright 필수 (순수 HTTP 불가)
```

## 2. 기술 스택 선정

### 추천 구성

| 계층 | 기술 | 이유 |
|------|------|------|
| 목록 스크래핑 | **Selenium** (유지) | 기존 코드 호환, 안정적 |
| 상세 스크래핑 | **Selenium** (유지) | 문서 수집 로직 재사용 |
| TankAuction | **Playwright** (유지) | async 지원, 멀티탭 |
| HTTP 직접 호출 | **requests/aiohttp** (추가) | API 직접 호출 시 |
| 데이터 저장 | **ElasticSearch** (유지) | 기존 인프라 |
| 큐 시스템 | **Redis Streams** (유지) | 기존 파이프라인 |
| OCR | **Claude Vision API** (유지) | 문서 처리 |

### Selenium vs Playwright 판단

```
목록/상세 → Selenium 유지
  이유: 기존 코드 700+ 줄 재사용, 셀렉터 동일, 안정적

TankAuction → Playwright 유지
  이유: async 필수, 멀티 윈도우 팝업 처리, 기존 코드 안정적
```

## 3. 봇 감지 우회 전략

### 기존 전략 유지 (유효)
```python
# web_driver.py에서 이미 구현됨
options.add_argument('--disable-blink-features=AutomationControlled')
options.add_experimental_option("excludeSwitches", ["enable-automation"])
driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
```

### 추가 권장 사항
```python
# 1. 요청 간 랜덤 딜레이 (기존 2-4초 유지)
delay = base_delay * (1 + random.uniform(-0.3, 0.3))

# 2. 세션 로테이션 (법원별)
# 법원 전환 시 새 세션 시작 → 자연스러운 사용 패턴

# 3. User-Agent 로테이션
USER_AGENTS = [
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ...',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ...',
]

# 4. PCA_PASS 대응
# 사이트에 PCA_PASS 플래그 발견 → 보안 체크 모니터링 필요
# 실패 시 세션 재생성 로직 추가
```

## 4. 데이터 파이프라인 설계

### 현재 파이프라인 (유지)
```
[List Scraper]
  ↓ HTML 파일 저장
[List Parser]
  ↓ 사건 목록 추출
[Redis Stream: scrape_queue]
  ↓
[Page Scraper Worker]
  ↓ 상세 HTML + PDF 수집
[Redis Stream: scrape2_queue]
  ↓
[TankAuction Worker]
  ↓ 등기/세대/건축물대장 PDF
[Redis Stream: parse_queue]
  ↓
[Page Parser Worker]
  ↓ OCR + 구조화 데이터 추출
[ElasticSearch]
```

### 개선 파이프라인 (제안)
```
[List Scraper] ←── 개선: API 직접 호출 옵션 추가
  ↓ JSON 데이터 직접 저장 (HTML 파싱 생략 가능)
[Redis Stream: scrape_queue]
  ↓
[Page Scraper Worker] ←── 개선: WebSquare JSON 추출 추가
  ↓ JSON + PDF 수집
[Redis Stream: scrape2_queue]
  ↓
[TankAuction Worker] ←── 유지
  ↓ PDF
[Redis Stream: parse_queue]
  ↓
[Page Parser Worker] ←── 유지
  ↓ OCR
[ElasticSearch]
```

## 5. 에러 처리 및 재시도 전략

### 기존 전략 (유지)
```python
# 3회 재시도 with exponential backoff
MAX_RETRIES = 3
RETRY_DELAYS = [5, 15, 30]  # 초

# 에러 분류
RETRIABLE_ERRORS = [
    'TIMEOUT',           # 페이지 로드 타임아웃
    'STALE_ELEMENT',     # DOM 변경
    'NO_SUCH_ELEMENT',   # 요소 미발견 (일시적)
]

FATAL_ERRORS = [
    'SESSION_EXPIRED',   # 세션 만료 → 새 세션
    'BLOCKED',           # 차단됨 → IP 변경 필요
    'SITE_DOWN',         # 사이트 다운
]
```

### 추가 에러 핸들링
```python
# PCA_PASS 실패 대응
if 'PCA' in page_source or captcha_detected():
    logger.warning("보안 체크 감지 → 세션 재생성")
    driver.quit()
    time.sleep(random.uniform(60, 120))  # 1-2분 대기
    driver = create_new_driver()

# WebSquare 로딩 실패
if not wait_for_websquare_ready(driver, timeout=30):
    logger.warning("WebSquare 로딩 실패 → 페이지 새로고침")
    driver.refresh()
    time.sleep(5)
```

## 6. 스케줄링 방안

```
일일 스크래핑 스케줄:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
06:00  목록 스크래핑 (전체 법원 순회)
       - detail: 현재 경매 물건
       - planned: 매각예정
       - result: 매각결과 (ES 최신 날짜 이후만)

10:00  상세 페이지 스크래핑 (새로 발견된 물건)
       - Worker 5대 병렬 처리
       - Redis Queue 기반

14:00  TankAuction PDF 수집
       - 등기/세대/건축물대장
       - 배치 로그인 (1회/세션)

18:00  OCR 처리 + 데이터 파싱
       - Claude Vision API
       - 구조화 데이터 ES 색인

02:00  정리
       - 임시 파일 정리
       - 오류 리포트 생성
       - ES 인덱스 최적화
```

## 7. 코드 뼈대 설계

### 개선된 List Scraper (API 직접 호출 옵션)

```python
# court_list_scraper/src/scrapers/api_list_scraper.py

class APIListScraper(BaseListScraper):
    """
    검색 API 직접 호출 방식 (Selenium 대안)
    세션 쿠키는 초기 1회 Selenium 접속으로 획득
    """

    def __init__(self, court_code: str, scrape_type: str = "detail"):
        self.session = requests.Session()
        self.base_url = "https://www.courtauction.go.kr"
        self.search_api = "/pgj/pgjsearch/searchControllerMain.on"

    def _acquire_session(self):
        """Selenium으로 1회 접속하여 세션 쿠키 획득"""
        driver = AuctionWebDriver.create()
        driver.get(f"{self.base_url}/pgj/index.on")
        time.sleep(3)
        # 쿠키 복사
        for cookie in driver.get_cookies():
            self.session.cookies.set(cookie['name'], cookie['value'])
        driver.quit()

    def search(self, court_code: str, page: int = 1, page_size: int = 40):
        """API 직접 호출로 검색"""
        payload = {
            "dma_pageInfo": {
                "pageNo": page,
                "pageSize": page_size,
                "totalYn": "Y" if page == 1 else "N",
            },
            "dma_srchGdsDtlSrchInfo": {
                "rletCortOfc": court_code,
                "bidDvsCd": "001",
                "mvprpRletDvsCd": "0001",
            }
        }
        resp = self.session.post(
            f"{self.base_url}{self.search_api}",
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        return resp.json()

    def scrape_all_pages(self, court_code: str):
        """전체 페이지 순회"""
        first = self.search(court_code, page=1)
        total = first['dma_pageInfo']['totalCnt']
        results = first['dlt_srchResult']

        max_pages = math.ceil(total / 40)
        for page in range(2, max_pages + 1):
            time.sleep(random.uniform(1, 3))
            data = self.search(court_code, page=page)
            results.extend(data['dlt_srchResult'])

        return results
```

### WebSquare JSON 추출 (상세 페이지용)

```python
# court_page_scraper/src/extractors/websquare_extractor.py

class WebSquareExtractor:
    """WebSquare DataList에서 직접 JSON 추출"""

    @staticmethod
    def extract_datalist(driver, component_id: str) -> list:
        """WebSquare DataList를 JSON으로 추출"""
        script = f"""
        try {{
            var comp = $p.getComponentById('{component_id}');
            if (comp) return JSON.stringify(comp.getJSON());
            return '[]';
        }} catch(e) {{ return '[]'; }}
        """
        result = driver.execute_script(f"return {script}")
        return json.loads(result)

    @staticmethod
    def extract_datamap(driver, component_id: str) -> dict:
        """WebSquare DataMap을 JSON으로 추출"""
        script = f"""
        try {{
            var comp = $p.getComponentById('{component_id}');
            if (comp) return JSON.stringify(comp.getJSON());
            return '{{}}';
        }} catch(e) {{ return '{{}}'; }}
        """
        result = driver.execute_script(f"return {script}")
        return json.loads(result)
```

## 8. 실행 우선순위

```
Phase 1 (즉시): 기존 코드 검증
  - 기존 셀렉터 동작 확인 (dry-run)
  - PCA_PASS 보안 체크 확인
  - 기존 파이프라인 정상 동작 검증

Phase 2 (1주): API 직접 호출 테스트
  - searchControllerMain.on API 직접 호출 PoC
  - 세션 관리 방안 검증
  - 성능 비교 (Selenium vs API)

Phase 3 (2주): 코드 개선
  - APIListScraper 구현 (Selenium fallback 유지)
  - WebSquareExtractor 통합
  - 에러 핸들링 강화

Phase 4 (3주): 운영 안정화
  - 스케줄러 설정
  - 모니터링 알림
  - 성능 최적화
```
