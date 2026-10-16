# CLAUDE.md — Training_2D_DMA

## 프로젝트 목표
- 교육TF의 신규 입사자 실습 교육 자료. 대상은 AXI 2D DMA의 RTL, TB, 문서다.
- SoC Design/Verification 전문가로서 정확하게 답하고, Junior Engineer가 이해할 수 있게 쉽게 설명한다.
- 공개(오픈소스) 저장소다. 비밀번호, 토큰, 사내 정보, 개인 Drive 링크는 커밋하지 않는다.

## 저장소 구조
| 경로 | 내용 |
|---|---|
| `RTL/` | `axi_dma.sv`(top), `adma_*.sv` |
| `RTL/common/` | 공용 IP (skid_buffer, sync_fifo, axi4_ctrl 등) |
| `TB/` | Verilator TB (`tb_*.sv`, `tb_ref.cpp` DPI 참조 모델), runner(`*.py`), `env/` 이미지 변환 스크립트 |
| `DOC/` | HDD(`HDD_2DDMA_v2.0.docx`), 검토 보고서와 버그 보고서(md) |

기준 DUT 구성(`TB/tb_var.sv`): 2 channel, AXI4→AXI4, 256-bit data, `ROB_EN=0`, `ATX_NUM_OSTD=2`, `DMA_DESC_DEPTH=4`.
실습 범위는 AXI4 구성(`SRC_IF_TYPE = DST_IF_TYPE = "AXI4"`)만이다. AXI4-Stream(AXIS)은 사용하지 않는다.

## 핵심 결정
1. **`main` = 안정 기준.** RTL/TB 변경은 `main`에 직접 커밋하지 않는다. 작업 브랜치에서 진행하고, 완료 기준을 만족하면 PR로 병합한다.
2. **수정본을 별도 폴더로 복사하지 않는다.** (`NEW_RTL/` 같은 폴더 금지) 버전 차이는 브랜치와 diff로 관리한다.
3. **변경 1건 = 브랜치 1개.** 이름은 `fix/<요약>` 또는 `feature/<요약>`이다. RTL 수정과 그것을 검증하는 TB 변경은 같은 브랜치에 둔다.
4. **zip, 빌드 산출물, 시뮬레이션 결과는 커밋하지 않는다.** (`build_byte/`, `run_byte/`, `results/`, `*.vcd`, `*.zip`)
5. **AXIS 관련 버그는 문서에 기록만 한다.** AXIS 경로(`adma_dm_src_axis.sv`, `adma_dm_dst_axis.sv`, `*_IF_TYPE == "AXIS"`일 때만 동작하는 코드)의 버그는 RTL을 수정하지 않고 TB도 만들지 않는다. DOC에 "범위 외(AXIS)"로 표기하고 원인 위치와 수정안만 적는다.
6. **알려진 이슈:** `BUG-AXI-W-001`(WVALID가 WREADY에 의존)은 `feature/wvalid-fix`에서 수정했다. `adma_dm_dst_axis.sv`의 TVALID→TREADY 의존(R-1)은 범위 외(AXIS)이므로 수정하지 않는다(문서 기록 완료).

## 작업 순서 (매 변경마다 반복)
RTL 분석 → TB 작성 → 검증(버그 재현) → 문서화 → RTL 수정 → 문서화 → 재검증 → 문서화

완료 기준: 수정 전 RTL에서 재현 테스트가 FAIL하고, 수정 후 같은 테스트와 기존 회귀가 모두 PASS한다. 결과는 DOC에 기록한다.

## RTL 코딩 규칙
- 기존 파일의 스타일을 따른다: 4-space 들여쓰기(tab 없음), active-low 비동기 Reset (`always @(posedge clk or negedge rst_n)`). Clock/Reset 이름은 top(`axi_dma`)에서 `aclk`/`aresetn`, 하위 모듈에서 `clk`/`rst_n`이다.
- 이름 규칙: 외부 AXI 포트는 `_i`/`_o` 접미사(`m_wvalid_o`, `m_wready_i`)를 쓰고, 내부 handshake 신호는 `*_vld`/`*_rdy`를 쓴다.
- **AXI 규칙:** VALID 생성식에 같은 채널의 READY를 넣지 않는다. VALID와 payload는 handshake까지 유지한다. 소비(pop, count 증가)는 `valid & ready`에서만 일어나야 한다.
- 수정한 줄에는 이유를 영문 주석 1~2줄로 남긴다.
- 요청 없이 parameter 기본값이나 포트를 바꾸지 않는다. `RTL/common/` 수정은 먼저 확인을 받는다.

## TB / 검증 규칙
- Simulator: Verilator 5.x (`--binary --timing --assert`), Python 3.9 이상.
- Verilator는 2-state라서 X/Reset 동작은 검증되지 않는다. 그 점을 문서에 명시한다.
- 새 시나리오는 `+SCENARIO=<NAME>`으로 추가한다. 이름을 넣을 때 `tb_seq.sv`, `tb_drv.sv`, runner의 `choices`를 함께 맞춘다.
- DUT 내부는 read-only probe로만 관찰한다. `force`/`release`는 쓰지 않는다.
- Known-bug FAIL을 PASS로 바꾸는 우회(waiver, 조건 완화)는 하지 않는다.
- 실행 예 (저장소 최상위에서):
  ```bash
  python3 TB/run_byte_tb.py --rtl-dir RTL --scenario CUSTOM
  python3 TB/run_wvalid_regression.py --rtl-dir RTL --out /tmp/wvalid_results   # feature/wvalid-fix
  ```
  exit code: 0 = PASS, 1 = DUT/test FAIL, 2 = setup/build 오류

## 문서 규칙 (DOC/)
- 파일명은 `<종류>_<대상>_<YYYYMMDD>.md` 형식이다. 예: `RTL_REVIEW_..._20261015.md`, `TB_REVIEW_..._20261015.md`
- ID 형식: 버그는 `BUG-<영역>-<채널>-<번호>`(예: `BUG-AXI-W-001`), 검토 항목은 TB `T-n`, RTL `R-n`, 참고 `I-n`이다. 심각도는 High/Medium/Low/Info로 표기한다.
- 시뮬레이션을 실제로 실행했는지, 정적 검토인지 반드시 적는다. PASS/FAIL 수치는 실행 로그를 근거로 쓴다.
- 기술 용어는 영어로 쓴다(Clock, Reset, Arbitration, Register 등). 비유 표현은 쓰지 않는다.
- AXI 근거는 IHI 0022(AXI4), IHI 0051(AXI4-Stream)의 절 번호로 인용한다.
