# Section 3: 기존 CourtAuction 코드 비교 분석

> 참조: `/Users/tony/Desktop/src/CUR_hit/CourtAuction/`

## 1. 기존 아키텍처 구조

```
CourtAuction/
├── court_list_scraper/     # 목록 스크래핑 (검색 결과 페이지)
│   ├── src/scrapers/
│   │   ├── base_list_scraper.py    # 추상 베이스
│   │   ├── list_scraper.py         # 상세 목록
│   │   ├── list_scraper_planned.py # 매각예정
│   │   └── list_scraper_result.py  # 매각결과
│   └── scripts/
│       └── list_scrape.py          # 엔트리포인트
│
├── court_page_scraper/     # 상세 페이지 스크래핑
│   └── src/scrapers/
│       ├── detail_selenium_scraper.py   # 기본 상세
│       └── enhanced_detail_scraper.py   # 확장 상세 (문서 수집)
│
├── common/
│   ├── drivers/web_driver.py       # Chrome WebDriver 설정
│   └── scrapers/selenium_scraper.py # Selenium 베이스
│
└── utils/
    ├── tankauction/scraper.py      # TankAuction PDF (Playwright)
    ├── ocr/                        # PDF OCR 처리
    └── navermap/                   # 네이버맵 연동
```

## 2. 핵심 사이트 접근 방식 (중요)

### 대법원 사이트 특성
- **WebSquare SPA** → URL 직접 접근 불가
- **메뉴 네비게이션 필수** → JavaScript 실행 환경 필요
- **세션 기반** → 쿠키/세션 유지 필수
- **동적 렌더링** → DOM이 JavaScript로 생성됨

### 기존 코드의 접근 방식
```python
# 1. 브라우저 열기 → 메인 페이지 접속
driver.get("https://www.courtauction.go.kr/pgj/index.on?w2xPath=/pgj/ui/pgj100/PGJ151F00.xml")

# 2. 검색 폼에서 법원 선택 (Selenium wait + click)
court_select = WebDriverWait(driver, 30).until(
    EC.presence_of_element_located((By.ID, "mf_wfm_mainFrame_sbx_rletCortOfc"))
)

# 3. 검색 실행 (button click)
search_btn = driver.find_element(By.ID, "mf_wfm_mainFrame_btn_gdsDtlSrch")

# 4. 결과 대기 + HTML 추출
# page_source로 전체 HTML 가져오기
```

## 3. 기존 셀렉터 vs 현재 사이트 비교

### ID 프리픽스 패턴
기존 코드에서 WebSquare 컴포넌트 ID에 `mf_wfm_mainFrame_` 프리픽스가 붙음:
- XML 정의: `sbx_rletCortOfc`
- 실제 DOM: `mf_wfm_mainFrame_sbx_rletCortOfc`

### 셀렉터 유효성

| 기존 셀렉터 | 현재 상태 | 비고 |
|------------|----------|------|
| `mf_wfm_mainFrame_sbx_rletCortOfc` (법원) | ✅ 유효 | XML에 `sbx_rletCortOfc` 확인됨 |
| `mf_wfm_mainFrame_sbx_rletCsYear` (연도) | ✅ 유효 | XML에 `sbx_rletCsYear` 확인됨 |
| `mf_wfm_mainFrame_ibx_rletCsNo` (사건번호) | ✅ 유효 | XML에 `ibx_rletCsNo` 확인됨 |
| `mf_wfm_mainFrame_btn_gdsDtlSrch` (검색) | ✅ 유효 | XML에 `btn_gdsDtlSrch` 확인됨 |
| `[data-col_id='maemulSer']` (물건번호) | ✅ 유효 | 그리드 컬럼 확인됨 |
| `sbx_pageSize` (페이지사이즈) | ✅ 유효 | XML에 확인됨 |
| 정렬 버튼 (headerSortSch) | ✅ 유효 | JS 함수 확인됨 |

### 결론: **기존 셀렉터 대부분 유효**
WebSquare XML 구조에서 동일한 컴포넌트 ID가 확인됨. 사이트 구조 변경은 없는 것으로 판단.

## 4. 스크래핑 타입별 비교

### A. 목록 스크래핑 (List Scraper)

| 항목 | 기존 코드 | 사이트 현황 | Gap |
|------|----------|------------|-----|
| 검색 API | Selenium 폼 제출 | POST searchControllerMain.on | **직접 API 호출 가능성** |
| 페이지 사이즈 | 40건 설정 | 10/20/30/40 지원 | 동일 |
| 정렬 | 클릭으로 asc/desc | headerSortSch() JS 호출 | 동일 |
| 페이지 이동 | 페이지 번호 클릭 | pgl 컴포넌트 이벤트 | 동일 |
| 데이터 추출 | page_source HTML 파싱 | JSON 응답 직접 파싱 가능 | **개선 가능** |
| 3가지 타입 | detail/planned/result | 동일 구조 유지 | 동일 |

### B. 상세 페이지 스크래핑 (Page Scraper)

| 항목 | 기존 코드 | 사이트 현황 | Gap |
|------|----------|------------|-----|
| 사건 검색 | 법원+연도+번호 입력 | 동일 구조 | 동일 |
| 물건 클릭 | moveDtlPage(index) | moveDtlPage() 확인됨 | 동일 |
| 문서 수집 | 5종 (현황조사, 감정, 매각명세, 전체HTML, 사건상세) | 동일 | 동일 |
| PDF 다운로드 | iframe src 추출 + 직접 다운 | 동일 방식 예상 | 확인 필요 |
| 이미지 수집 | 페이지별 추출 + 중복 감지 | 동일 | 동일 |

### C. TankAuction 연동

| 항목 | 기존 코드 | 현황 | Gap |
|------|----------|------|-----|
| 로그인 | username/password | 동일 | 동일 |
| 4종 문서 | DB/DA/EA/EC | 동일 | 동일 |
| 브라우저 | Playwright (async) | 동일 | 동일 |
| PDF 다운로드 | aiohttp 직접 다운 | 동일 | 동일 |

## 5. 발견된 개선 기회

### 5.1 검색 API 직접 호출 (가장 큰 개선 포인트)

현재 사이트에서 확인된 검색 API:
```
POST /pgj/pgjsearch/searchControllerMain.on
```
이 API가 JSON 요청/응답을 지원하므로, **Selenium 없이 직접 HTTP 호출**이 가능할 수 있음.

**장점:**
- 속도 10배 이상 향상
- 브라우저 메모리 불필요
- 병렬 처리 용이

**제약:**
- 세션/쿠키 관리 필요 (초기 1회 브라우저 접속으로 세션 획득)
- WebSquare 내부 토큰이 필요할 수 있음

### 5.2 데이터 추출 방식 개선

기존: HTML page_source → BeautifulSoup 파싱
개선: WebSquare DataList에서 직접 JSON 추출

```javascript
// 브라우저 콘솔에서:
$p.getComponentById('dlt_srchResult').getJSON()
```

### 5.3 봇 감지 우회 (기존 코드 유지)

기존 코드의 우회 전략이 이미 충분:
- `AutomationControlled` 비활성화
- `navigator.webdriver` 제거
- 자연스러운 User-Agent
- 랜덤 딜레이 (2-4초 ±30%)

## 6. 유지 가능한 기존 코드

| 모듈 | 재사용 가능 여부 | 이유 |
|------|:---:|------|
| `web_driver.py` | ✅ | 봇 감지 우회 설정 그대로 유효 |
| `base_list_scraper.py` | ✅ | 구조 동일 |
| `list_scraper.py` | ✅ | 셀렉터 유효 |
| `detail_selenium_scraper.py` | ✅ | moveDtlPage 동일 |
| `enhanced_detail_scraper.py` | ✅ | 문서 수집 로직 동일 |
| `tankauction/scraper.py` | ✅ | 별도 사이트, 변경 없음 |
| OCR 모듈 | ✅ | 사이트 무관, 문서 처리 로직 |
| Redis Queue 시스템 | ✅ | 인프라 레벨 |

## 7. 깨진 기능 또는 위험 요소

| 위험 | 심각도 | 설명 |
|------|--------|------|
| WebSquare 버전 업그레이드 | 중 | ID 프리픽스 변경 가능성 |
| PCA_PASS 보안 체크 | 중 | 새로운 봇 감지 메커니즘 가능 |
| PDF iframe 구조 변경 | 저 | PDF 다운로드 방식 변경 가능 |
| 법원코드 변경 | 저 | 법원 통폐합 시 코드 변경 |
