# Section 2: 데이터 포인트 및 API 매핑

## 1. 검색 결과 목록 데이터 (dlt_srchResult)

### 핵심 필드 매핑 (110+ 컬럼 중 주요)

| 필드명 | 타입 | 설명 | 스크래핑 우선도 |
|--------|------|------|----------------|
| `saNo` | string | 사건번호 (원본) | ★★★ |
| `printCsNo` | string | 사건번호 (표시용) | ★★★ |
| `mokmulSer` | string | 물건번호 (시리얼) | ★★★ |
| `maemulSer` | string | 매물번호 | ★★★ |
| `cortOfcCd` | string | 법원코드 | ★★★ |
| `jpDeptNm` | string | 담당부서명 | ★★ |
| `realSt` | string | 소재지 (실주소) | ★★★ |
| `printSt` | string | 소재지 (표시용) | ★★ |
| `gamevalAmt` | number | 감정평가액 | ★★★ |
| `notifyMinmaePrice1` | number | 최저매각가 | ★★★ |
| `lclsUtilCd` | string | 대분류 용도코드 | ★★★ |
| `mclsUtilCd` | string | 중분류 용도코드 | ★★ |
| `dspslUsgNm` | string | 용도명 | ★★ |
| `dspslDxdyYmd` | string | 매각기일 | ★★★ |
| `flbdNcnt` | number | 유찰횟수 | ★★ |
| `dspslGdsSeq` | string | 물건 시퀀스 | ★★★ |
| `mulBigo` | string | 비고 | ★ |

### 데이터 리스트 전체 컬럼 (확인된 것)
```
saNo, mokmulSer, csNo, printCsNo, maemulSer, realSt, printSt,
gamevalAmt, notifyMinmaePrice1, cortOfcCd, jpDeptNm,
dspslDxdyYmd, dspslUsgNm, lclsUtilCd, mclsUtilCd, sclsUtilCd,
flbdNcnt, mulBigo, dspslGdsSeq, mapBtn, checkBox,
rletDspslSpcCondCd, bidDvsCd, mvprpRletDvsCd,
adongSdS, adongSggS, adongEmdS, adongSdR, adongSggR, adongRdnm,
aeeEvlAmt, lwsDspslPrc, lwsRate, ...
```

## 2. 검색 API 상세

### POST /pgj/pgjsearch/searchControllerMain.on

**요청 구조:**
```json
{
  "dma_pageInfo": {
    "pageNo": 1,
    "pageSize": 40,
    "totalYn": "Y",
    "bfPageNo": 0
  },
  "dma_srchGdsDtlSrchInfo": {
    "rletCortOfc": "법원코드",
    "rletCortOfcDept": "부서코드",
    "rletCsYear": "2024",
    "rletCsNo": "104243",
    "bidDvsCd": "001",
    "mvprpRletDvsCd": "0001",
    "rletAdongSdS": "시도코드",
    "rletAdongSggS": "시군구코드",
    "rletAdongEmd": "읍면동코드",
    "rletLclLst": "대분류",
    "rletMclLst": "중분류",
    "rletSclLst": "소분류",
    "rletArMin": "",
    "rletArMax": "",
    "rletAeePyngEqvalMin": "",
    "rletAeePyngEqvalMax": "",
    "rletLwsDspslMin": "",
    "rletLwsDspslMax": "",
    "rletLwsRateMin": "",
    "rletLwsRateMax": "",
    "rletFlbdCntMin": "",
    "rletFlbdCntMax": "",
    "rletPerdStr": "",
    "rletPerdEnd": "",
    "rletDspslSpcCondCd": "",
    "lafjOrderBy": "정렬기준"
  }
}
```

**응답 구조:**
```json
{
  "dma_pageInfo": {
    "totalCnt": 1234,
    "startRowNo": 1,
    "groupTotalCount": 1234
  },
  "dlt_srchResult": [
    {
      "saNo": "2024타경104243",
      "mokmulSer": "1",
      "cortOfcCd": "207",
      "realSt": "서울특별시 강남구...",
      "gamevalAmt": 500000000,
      "notifyMinmaePrice1": 400000000,
      "dspslDxdyYmd": "2026-03-15",
      "flbdNcnt": 2,
      "dspslUsgNm": "아파트",
      ...
    }
  ]
}
```

## 3. 상세 페이지 데이터

### 상세 이동 파라미터
```
PGJ15BM01.xml?csNo={saNo}&cortOfcCd={cortOfcCd}&dspslGdsSeq={seq}&lclsUtilCd={lcd}&mclsUtilCd={mcd}
```

### 상세 페이지 내 문서 유형

| 문서 | 형식 | 접근 방식 |
|------|------|----------|
| 현황조사서 | HTML | iframe 내 렌더링 |
| 감정평가서 | PDF | iframe src → PDF URL 추출 |
| 매각물건명세서 | PDF | iframe src → PDF URL 추출 |
| 사건상세조회 | HTML | 페이지 내 렌더링 |
| 건물등기 | PDF | TankAuction 연동 |
| 토지등기 | PDF | TankAuction 연동 |
| 세대열람 | PDF | TankAuction 연동 |
| 건축물대장 | PDF | TankAuction 연동 |

## 4. 페이지네이션

- 컴포넌트: `pgl_gdsDtlSrchPage`
- 페이지 사이즈: 10/20/30/40 (`sbx_pageSize`)
- 이벤트: `pgl_gdsDtlSrchPage_onviewchange()` → pageNo 업데이트 → 재검색
- 쿠키 저장: `pageCnt` 쿠키에 페이지 사이즈 기억

## 5. 정렬

```javascript
headerSortSch(columnId) {
  // "order by {columnId} asc|desc" 구성
  // dma_srchGdsDtlSrchInfo.lafjOrderBy에 설정
  // 재검색 실행
}
```
- 정렬 토글: asc ↔ desc (아이콘 변경)
- 기본 정렬: 매각기일 기준

## 6. CSS 셀렉터 (Selenium/Playwright용)

```python
SELECTORS = {
    # 검색 폼
    'court_select': '#sbx_rletCortOfc',            # By.ID
    'dept_select': '#sbx_rletCortOfcDept',
    'year_select': '#sbx_rletCsYear',
    'case_number': '#ibx_rletCsNo',
    'search_button': '#btn_gdsDtlSrch',
    'reset_button': '#btn_rletInit',

    # 결과 그리드
    'result_grid': '#grd_gdsDtlSrchResult',
    'maemul_cells': '[data-col_id="maemulSer"]',
    'case_no_cells': '[data-col_id="printCsNo"]',

    # 페이지네이션
    'page_size': '#sbx_pageSize',
    'page_nav': '#pgl_gdsDtlSrchPage',

    # 정렬
    'sort_header': '.w2grid_header [data-col_id]',
}
```
