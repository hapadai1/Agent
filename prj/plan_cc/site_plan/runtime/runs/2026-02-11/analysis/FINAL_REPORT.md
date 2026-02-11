# courtauction.go.kr 스크래핑 전략 최종 리포트

> 분석일: 2026-02-11
> 분석자: Claude (사이트 분석 + 코드 비교 + 전략 수립)
> 참조: /Users/tony/Desktop/src/CUR_hit/CourtAuction/

---

## 핵심 결론

### 1. 기존 CourtAuction 코드는 대부분 유효하다
- 모든 주요 셀렉터(`sbx_rletCortOfc`, `ibx_rletCsNo`, `btn_gdsDtlSrch` 등)가 현재 사이트 XML에서 확인됨
- `moveDtlPage()` 상세 이동 함수 동일
- WebSquare 프레임워크 구조 변경 없음
- 기존 파이프라인(List→Page→TankAuction→OCR→ES) 그대로 사용 가능

### 2. 사이트 접근 방식의 핵심 제약
```
⚠️ 메뉴 접근은 가능하나, 세부 데이터는 UI 조작 필수
  - 법원 선택 → 검색 조건 입력 → 검색 버튼 클릭 → 결과 로딩 대기
  - 페이지 이동 → 상세 클릭 → 문서 탭 전환 → PDF 다운로드
  → Selenium/Playwright 필수 (순수 HTTP 요청 불가)
```

### 3. 가장 큰 개선 기회: 검색 API 직접 호출
```
현재: Selenium으로 폼 입력 → 클릭 → HTML 파싱 (느림)
개선: POST /pgj/pgjsearch/searchControllerMain.on (빠름)
  - 세션 쿠키만 있으면 JSON 직접 호출 가능
  - 초기 1회 Selenium 접속 → 쿠키 획득 → 이후 HTTP 직접 호출
  - 예상 성능: 10배 이상 향상
```

---

## 사이트 구조 요약

| 항목 | 내용 |
|------|------|
| URL | `https://www.courtauction.go.kr/pgj/index.on` |
| 프레임워크 | WebSquare 5 (SPA) |
| UI 정의 | XML 파일 (`/pgj/ui/pgj100/*.xml`) |
| 검색 API | `POST /pgj/pgjsearch/searchControllerMain.on` |
| 데이터 모델 | `dma_srchGdsDtlSrchInfo` (60+ 필드) |
| 결과 모델 | `dlt_srchResult` (110+ 컬럼) |
| 상세 이동 | `moveDtlPage(index)` → PGJ15BM01.xml |
| 문서 유형 | HTML 3종 + PDF 5종 + TankAuction PDF 4종 |

---

## 스크래핑 대상 데이터

### 목록 데이터 (검색 결과)
| 필드 | 설명 | 우선도 |
|------|------|--------|
| saNo | 사건번호 | ★★★ |
| cortOfcCd | 법원코드 | ★★★ |
| realSt | 소재지 | ★★★ |
| gamevalAmt | 감정가 | ★★★ |
| notifyMinmaePrice1 | 최저매각가 | ★★★ |
| dspslDxdyYmd | 매각기일 | ★★★ |
| dspslUsgNm | 용도 | ★★ |
| flbdNcnt | 유찰횟수 | ★★ |
| maemulSer | 물건번호 | ★★★ |

### 상세 문서
| 문서 | 소스 | 형식 |
|------|------|------|
| 현황조사서 | 대법원 사이트 | HTML |
| 감정평가서 | 대법원 사이트 | PDF |
| 매각물건명세서 | 대법원 사이트 | PDF |
| 사건상세조회 | 대법원 사이트 | HTML |
| 전체HTML | 대법원 사이트 | HTML |
| 건물등기 | TankAuction | PDF |
| 토지등기 | TankAuction | PDF |
| 세대열람 | TankAuction | PDF |
| 건축물대장 | TankAuction | PDF |

---

## 스크래핑 전략

### Phase 1: 기존 코드 검증 (즉시)
```bash
# 기존 셀렉터 동작 확인
cd /Users/tony/Desktop/src/CUR_hit/CourtAuction
python -m court_list_scraper.scripts.list_scrape --court=207 --type=detail --dry-run

# PCA_PASS 보안 체크 확인
# 기존 파이프라인 정상 동작 검증
```

### Phase 2: API 직접 호출 PoC (1주)
```python
# 새 모듈: court_list_scraper/src/scrapers/api_list_scraper.py
# 세션 쿠키 획득 → searchControllerMain.on 직접 호출
# 성능 비교: Selenium(현재) vs API(새)
```

### Phase 3: 코드 개선 (2주)
- APIListScraper 구현 (Selenium fallback 유지)
- WebSquare DataList JSON 직접 추출
- 에러 핸들링 강화 (PCA_PASS 대응)

### Phase 4: 운영 안정화 (3주)
- cron 스케줄러 설정
- 모니터링 알림
- 성능 최적화

---

## 기술 스택

| 계층 | 기술 | 비고 |
|------|------|------|
| 목록 스크래핑 | Selenium → API 직접 호출 (점진) | 기존 유지 + 개선 |
| 상세 스크래핑 | Selenium | UI 조작 필수 |
| TankAuction | Playwright (async) | 기존 유지 |
| HTTP | requests / aiohttp | API 직접 호출 |
| 저장 | ElasticSearch | 기존 유지 |
| 큐 | Redis Streams | 기존 유지 |
| OCR | Claude Vision API | 기존 유지 |
| 봇 우회 | AutomationControlled 비활성화 + 랜덤 딜레이 | 기존 유지 |

---

## 주의사항

1. **UI 조작 필수**: 검색 결과, 상세 정보는 반드시 브라우저에서 폼 조작 → 클릭 → 대기 → 추출 순서
2. **WebSquare ID 프리픽스**: XML에서 `sbx_rletCortOfc` → 실제 DOM은 `mf_wfm_mainFrame_sbx_rletCortOfc`
3. **PCA_PASS 보안**: 새로운 봇 감지 가능성 → 세션 재생성 로직 준비
4. **API 직접 호출**: 반드시 유효한 세션 쿠키 필요 → 초기 Selenium 1회 접속 필수
5. **TankAuction 별도**: 대법원과 별개 사이트, Playwright로 별도 처리

---

## 파일 구조

```
projects/site_plan/runtime/runs/2026-02-11/analysis/
├── s1_site_v1.out.md          # 사이트 구조 분석
├── s2_data_v1.out.md          # 데이터 포인트 매핑
├── s3_compare_v1.out.md       # 기존 코드 비교
├── s4_strategy_v1.out.md      # 스크래핑 전략
└── FINAL_REPORT.md            # 이 파일 (최종 리포트)
```
