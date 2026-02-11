# Section 1: courtauction.go.kr 사이트 구조 분석

## 1. 프레임워크

**WebSquare 5 기반 SPA (Single Page Application)**
- 엔트리포인트: `https://www.courtauction.go.kr/pgj/index.on`
- baseURI: `/pgj/websquare/`
- UI 정의: XML 파일 기반 (`/pgj/ui/pgj100/*.xml`)
- 데이터 바인딩: WebSquare DataMap/DataList 모델 사용

## 2. 페이지 구조 (URL → XML 매핑)

```
index.on (엔트리)
  └── PGJ151F00.xml (마스터 프레임 - 라우터)
        ├── PGJ151F01.xml   ← 검색 폼 (부동산/동산)
        ├── PGJ151M01.xml   ← 부동산 검색 결과 목록
        ├── PGJ151M02.xml   ← 동산 검색 결과 목록
        ├── PGJ15BM01.xml   ← 물건 상세 (부동산)
        ├── PGJ15BM04.xml   ← 물건 상세 (추가)
        ├── PGJ153F01.xml   ← 추가 검색
        ├── PGJ15AF01.xml   ← 관심물건
        ├── PGJ154M02.xml   ← 차량 상세
        └── PGJ154M03.xml   ← 차량 상세 (추가)
```

**라우팅 방식**: `$p.main().wfm_mainFrame.setSrc(xmlPath)` — JavaScript 기반 내부 프레임 전환. URL은 변경되지 않음.

## 3. 검색 폼 구조 (PGJ151F01.xml)

### 부동산 검색 탭

| 필드 | ID | 타입 | 설명 |
|------|-----|------|------|
| 법원 | `sbx_rletCortOfc` | select | 법원 선택 |
| 법원부서 | `sbx_rletCortOfcDept` | select | 부서 선택 |
| 사건연도 | `sbx_rletCsYear` | select | 연도 드롭다운 |
| 사건번호 | `ibx_rletCsNo` | input | 사건번호 입력 |
| 시/도 (등기) | `sbx_rletAdongSdS` | select | 시도 선택 |
| 시/군/구 (등기) | `sbx_rletAdongSggS` | select | 시군구 선택 |
| 읍/면/동 | `sbx_rletAdongEmd` | select | 읍면동 선택 |
| 시/도 (도로명) | `sbx_rletAdongSdR` | select | 시도 (도로명) |
| 시/군/구 (도로명) | `sbx_rletAdongSggR` | select | 시군구 (도로명) |
| 도로명 | `sbx_rletAdongRdnm` | select | 도로명 선택 |
| 초성 | `sbx_rletConsonant` | select | 초성 필터 |
| 용도 (대) | `sbx_rletLclLst` | select | 대분류 |
| 용도 (중) | `sbx_rletMclLst` | select | 중분류 |
| 용도 (소) | `sbx_rletSclLst` | select | 소분류 |
| 면적 (최소) | `ibx_rletArMin` | input | 면적 범위 시작 |
| 면적 (최대) | `ibx_rletArMax` | input | 면적 범위 끝 |
| 감정가 (최소) | `sbx_rletAeePyngEqvalMin` | select | 감정가 범위 |
| 감정가 (최대) | `sbx_rletAeePyngEqvalMax` | select | |
| 최저매각가 (최소) | `sbx_rletLwsDspslMin` | select | 최저가 범위 |
| 최저매각가 (최대) | `sbx_rletLwsDspslMax` | select | |
| 매각비율 (최소) | `sbx_rletLwsRateMin` | select | |
| 매각비율 (최대) | `sbx_rletLwsRateMax` | select | |
| 유찰횟수 (최소) | `sbx_rletFlbdCntMin` | select | |
| 유찰횟수 (최대) | `sbx_rletFlbdCntMax` | select | |
| 기간 (시작) | `cal_rletPerdStr` | calendar | 매각기일 |
| 기간 (종료) | `cal_rletPerdEnd` | calendar | |
| 소재지공고 (등기) | `cbx_rletPbancMidYnS` | checkbox | |
| 소재지공고 (도로명) | `cbx_rletPbancMidYnR` | checkbox | |
| 특수조건1 | `cbx_rletDspslSpcCondCd1` | checkbox | |
| 특수조건2 | `cbx_rletDspslSpcCondCd2` | checkbox | |
| 검색 | `btn_gdsDtlSrch` | button | 검색 실행 |
| 초기화 | `btn_rletInit` | button | 검색 초기화 |

### 동산 검색 탭

| 필드 | ID | 타입 | 설명 |
|------|-----|------|------|
| 집행관 | `sbx_mvprpCortOfc` | select | |
| 사건연도 | `sbx_mvprpCsYear` | select | |
| 사건번호 | `ibx_mvprpCsNo` | input | |
| 사건구분 | `sbx_mvprpCsDvs` | select | 601/602/603 |
| 매각일 (시작) | `cal_dspslDxdyStr` | calendar | |
| 매각일 (종료) | `cal_dspslDxdyEnd` | calendar | |
| 물건명 | `ibx_srchwd` | input | 키워드 검색 |
| 물건종류 | `sbx_mvprpArtclKnd` | select | |
| 매각장소유형 | `sbx_mvprpDspslPlcTyp` | select | |
| 입찰방법 | `rad_mvprpBidLst` | radio | |

## 4. 검색 결과 API (핵심)

### 엔드포인트
```
POST /pgj/pgjsearch/searchControllerMain.on
Content-Type: application/json
```

### 요청 데이터 모델
- `dma_pageInfo`: pageNo, pageSize(10/20/30/40), totalYn, bfPageNo
- `dma_srchGdsDtlSrchInfo`: 60+ 필드 (법원코드, 사건번호, 주소, 감정가, 면적 등)

### 응답 데이터 모델
- `dma_pageInfo`: totalCnt, startRowNo, groupTotalCount
- `dlt_srchResult`: 110+ 컬럼의 DataList
  - 주요 컬럼: saNo, mokmulSer, realSt, gamevalAmt, lclsUtilCd, mclsUtilCd, cortOfcCd, jpDeptNm, dspslDxdyYmd, flbdNcnt

### 결과 그리드 (grd_gdsDtlSrchResult)
| 표시 컬럼 | 데이터키 | 너비 | 설명 |
|-----------|----------|------|------|
| 체크박스 | checkBox | 40px | 선택 |
| 사건번호 | printCsNo | 115px | 포맷된 사건번호 |
| 물건번호 | maemulSer | 70px | 물건 시리얼 |
| 소재지 | printSt | 200px | 주소 (링크) |
| 지도 | mapBtn | 70px | 지도 버튼 |
| 비고 | mulBigo | 200px | 비고사항 |
| 감정가 | gamevalAmt | 110px | 감정 평가액 |
| 담당 | jpDeptNm | 100px | 담당부서+매각기일 |
| 용도 | dspslUsgNm | 70px | 용도 구분 |
| 최저매각가 | notifyMinmaePrice1 | 110px | 최저가+비율 |
| 진행상태 | yuchalCnt | 100px | 신건/유찰N회 |

## 5. 상세 페이지 네비게이션

```javascript
moveDtlPage(index) {
  // dlt_srchResult에서 행 데이터 추출
  csNo, cortOfcCd, dspslGdsSeq, lclsUtilCd, mclsUtilCd

  // 차량이면 PGJ154M03.xml, 아니면 PGJ15BM01.xml로 이동
  wfm_mainFrame.setSrc(targetXml + "?csNo=...&cortOfcCd=...")
}
```

## 6. 추가 API 엔드포인트

| 엔드포인트 | 용도 |
|-----------|------|
| `/pgj/pgj151/selectGdsDtlBmrkSrchCond.on` | 즐겨찾기 검색조건 조회 |
| `/pgj/pgj195/saveBmrkSrchCond.on` | 검색조건 저장 |
| `/pgj/pgj195/deleteBmrkSrchCond.on` | 검색조건 삭제 |
| `/pgj/pgjsearch/searchControllerMain.on` | **메인 검색 API** |

## 7. 봇 감지 관련

- WebSquare 프레임워크 특성상 일반 HTTP 요청으로는 데이터 접근 불가
- JavaScript 실행 환경 필요 (Selenium/Playwright 필수)
- 세션 기반 인증 (쿠키 관리 필요)
- `PCA_PASS` 플래그 → 보안 체크 존재 가능성
