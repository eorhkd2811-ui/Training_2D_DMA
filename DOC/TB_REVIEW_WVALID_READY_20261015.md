# TB 검토 보고서 — `TB_WVALID_READY_20261014`

| 항목 | 내용 |
|---|---|
| 검토일 | 2026-10-15 (Asia/Seoul) |
| 검토 대상 | 공유 폴더의 `TB_WVALID_READY_20261014/` 파일 18개 + 상위의 `BUG_AXI_WVALID_DEPENDS_ON_WREADY.md`, `README_WVALID_READY.md` (zip 제외) |
| 기준 DUT | 교육TF 프로젝트(현재 컨텍스트)에 등록된 RTL — `axi_dma.sv`, `adma_*.sv`, common(`skid_buffer.v`, `sync_fifo.v` 등) |
| 검토 방법 | 정적 코드 리뷰(소스 대조 + 신호 흐름 추적). **이번 검토에서 시뮬레이션은 직접 실행하지 않았다.** 실행 수치는 TB 작성자 문서에서 인용했다. |
| 결론 | **판정을 뒤집는 오류는 없다.** TB는 컨텍스트 DUT와 올바르게 연결되고, AXI 규칙을 지키는 Slave로 버그를 정당하게 재현한다. 개선 권장: Medium 2건, Low 2건, Info 4건 |

---

## 1. 한눈에 보는 결론

- ✅ 내부 probe 계층 경로, unit TB 포트(`.*`), 파라미터가 모두 컨텍스트 DUT와 일치한다.
- ✅ 새 Slave 정책("WVALID를 본 뒤 WREADY를 올림")은 AXI에서 **허용되는** 합법적 동작이다.
- ✅ Hold checker(VALID/payload 유지 검사)는 AXI 규칙을 정확히 구현했다.
- ✅ RTL을 건드리지 않는다(force/release, 계층 할당 없음, read-only probe만 사용).
- ⚠️ **T-1**: 검출 방식이 "증상(32-cycle 정체)" 기반이라, 대조군 테스트는 버그가 있어도 PASS한다. 원인(조합 경로)을 직접 잡는 검사를 추가하면 좋다.
- ⚠️ **T-2**: Unit TB가 현재 bypass 구조를 전제로 작성되어, 다른 구조의 수정안에 재사용하면 오판할 수 있다.

---

## 2. 배경 지식 (신입용 요약): VALID / READY 3가지 규칙

```text
규칙 1. 보내는 쪽(Master)은 READY를 기다렸다가 VALID를 올리면 안 된다.
규칙 2. 받는 쪽(Slave)은 VALID를 본 뒤에 READY를 올려도 된다.
규칙 3. VALID를 올렸으면 handshake(상승 edge에서 VALID=1 & READY=1)까지
        VALID와 데이터(WDATA/WSTRB/WLAST)를 바꾸면 안 된다.
```

원본 RTL에서 deadlock이 나는 이유:

```text
원본 RTL :  WVALID = data_vld & len_vld & WREADY   ← 규칙 1 위반 (READY가 VALID 식에 들어감)
새 Slave :  WREADY = "WVALID를 본 뒤 1"            ← 규칙 2, 합법

  Master: "READY가 와야 VALID를 올릴게"
  Slave : "VALID가 와야 READY를 올릴게"
  → 서로 기다림 = deadlock
```

기존 TB의 Slave는 항상 READY를 먼저 올렸기 때문에 이 버그가 숨어 있었다. 이번 TB는 규칙 2를 사용하는 Slave를 추가해서 버그를 드러냈다. 이 접근은 업계 VIP의 "ready-after-valid" 정책과 같은 방식이다.

---

## 3. TB ↔ 컨텍스트 DUT 정합성 확인

| # | 확인 항목 | TB 쪽 | 컨텍스트 DUT 쪽 | 결과 |
|---|---|---|---|---|
| 1 | 내부 probe 계층 경로 | `duv.dut.dm.wh.DST_AXI4_GEN.w.*` (`tb_top.sv`) | `tb_top.duv`(tb_duv) → `dut`(axi_dma) → `dm`(adma_data_mover) → `wh`(adma_dm_wr_host) → generate `DST_AXI4_GEN` → `w`(adma_dm_axi_w) | ✅ 일치 |
| 2 | probe 신호명 | `atx_wdata_vld`, `wdata_len_vld`, `atx_wdata_rdy` | `adma_dm_axi_w`의 포트/내부 wire로 존재 | ✅ 일치 |
| 3 | unit TB `.*` 포트 연결 | 12개 신호 선언 | `adma_dm_axi_w` 포트 12개 (clk, rst_n, atx_awlen, atx_vld, atx_rdy, atx_wdata, atx_wdata_vld, atx_wdata_rdy, m_wdata_o, m_wlast_o, m_wvalid_o, m_wready_i) | ✅ 이름·폭 일치 |
| 4 | 파라미터 | unit: LEN_W=8, DATA_W=256, OSTD=2 | `tb_var`: 2채널 → `ATX_NUM_OSTD=2` | ✅ 일치 |
| 5 | 원인 코드 위치 | 버그 문서: 40행 `SBUF_TYPE=4`, 75~77행 | 컨텍스트 `adma_dm_axi_w.sv` 40행, 75~77행 | ✅ 일치 |
| 6 | bypass 동작 | 문서 인용 | `skid_buffer.v` BYPASS: `fwd_valid_o = bwd_valid_i`, `bwd_ready_o = fwd_ready_i` | ✅ 일치 |
| 7 | 새 시나리오 분기 | `WREADY_WAIT_VALID`, `..._MID` | `tb_seq`: `IMG_STREAM`이 아니면 `custom_sequence()` + 합성 src_mem 패턴 사용 | ✅ CUSTOM descriptor 재사용 (의도대로) |
| 8 | 결과 판정 | 새 시나리오 이름 | `tb_sb`: `IMG_STREAM`일 때만 image format 파일 생성, 그 외는 공통 PASS 경로 | ✅ 문제 없음 |
| 9 | 기존 TB 보존 | 미변경 9개 / 변경 4개 | 미변경 파일 크기 = Latest TB manifest 크기. `tb_drv.sv`, `tb_top.sv`는 "컨텍스트 원본 + patch = Drive 사본"을 전체 내용으로 대조. `tb_seq.sv`, `run_byte_tb.py`는 patch 내용과 크기 증가분으로 대조 | ✅ 일치 |

> 참고: `tb_ref.cpp`, `tb_dpi.sv`는 크기가 원본과 같고 W 채널 경로와 무관하여 상세 내용 검토에서 제외했다.

---

## 4. 구성요소별 검토

### 4.1 Slave BFM — `tb_drv.sv` (`MEMORY_W_RECEIVE` 블록)

`WREADY_WAIT_VALID` 시나리오의 동작 순서:

1. AW handshake로 받은 burst 정보를 mailbox에서 꺼낸다. 즉 Slave는 **AW를 먼저 받은 뒤** W를 받는다. (Slave의 합법적 선택)
2. negedge에서 `WREADY=0`을 유지하고, posedge마다 `WVALID`를 관찰한다.
3. `WVALID=1`을 확인한 뒤 2 cycle 더 `WREADY=0`을 유지한다. 일부러 stall을 만들어 hold 검사를 동작시킨다.
4. negedge에서 `WREADY=1` → 다음 posedge에서 handshake.

| 확인 항목 | 판단 |
|---|---|
| AXI 합법성 | ✅ 규칙 2에 해당. Slave는 VALID를 보고 READY를 올릴 수 있다. |
| 조합 루프 방지 | ✅ READY를 negedge에서만 바꾼다. 만약 `WREADY = WVALID`처럼 조합으로 연결하면, 원본 RTL의 조합 경로와 루프가 생겨 시뮬레이터가 오판할 수 있다. 이를 피한 설계가 맞다. |
| 무한 대기 | ✅ 대기 루프 자체에는 timeout이 없지만, checker(32 cycles)와 `TIMEOUT_NS=200000`이 상한 역할을 한다. |
| MID 시나리오 의미 | ✅ `w_accepted`는 **시뮬레이션 전체 누적값**이다. 따라서 "전체에서 첫 beat 하나만 READY-first, 이후 모든 beat는 VALID 대기"다. burst마다 첫 beat를 READY-first로 한다는 뜻이 아니므로 교육 시 주의해서 설명한다. 문서 설명과는 일치한다. |

### 4.2 Checker — `tb_wvalid_check.sv`

두 가지 검사를 한다.

| 검사 | 조건 | 성격 |
|---|---|---|
| (1) 정체 검사 | `data_vld=1 & len_vld=1 & WREADY=0 & WVALID=0`이 연속 32회 → FAIL | AXI 규칙이 아닌 **진행 보장 진단**(TB 기준). 문서에 명시돼 있어 적절 |
| (2) Hold 검사 | 직전 edge에서 `WVALID=1 & WREADY=0`이면, 이번 edge에서도 `WVALID=1`이고 `{WDATA,WSTRB,WLAST}`가 같아야 함 | **규칙 3을 정확히 구현.** READY가 1이 된 수락 edge도 검사한다 |

- payload 비교 폭: `ATX_DST_DATA_W + ATX_DST_BYTE_AMT + 1 = 256 + 32 + 1 = 289 bit` ✅ (WDATA + WSTRB + WLAST)
- 리셋 중 카운터와 상태 초기화 ✅
- 정체 검사의 전제(`data_vld`, `len_vld`)로 "데이터가 없어서 멈춘 경우"와 구분한 점이 좋다 ✅

### 4.3 Unit TB — `tb_wvalid_unit.sv`

- 상류(upstream) 데이터는 handshake까지 유지한다 ✅ (실제 data FIFO와 같은 계약)
- 길이(metadata)를 먼저 넣고 데이터를 준다 (`wait(dut.wdata_len_vld)`) ✅
- WLAST 위치, 마지막 handshake 후 길이 FIFO가 비는 것까지 확인한다 ✅
- 단, 구조 의존성이 있다 → **T-2** 참고

### 4.4 Runner — `run_wvalid_regression.py`

- 알려진 버그 재현(FAIL)을 PASS로 바꾸지 않는다 ✅
- 실행 전후 RTL/common 파일 SHA-256 비교로 "RTL 미수정"을 증명한다 ✅
- full PASS 조건: exit code 0 + `[TB_PASS]`/`[IRQ_PASS]`/`[PRED SUMMARY]` 토큰 + `tb_result.txt` 존재 ✅
- `-Wno-fatal`로 경고가 있어도 build가 성공한다. 경고는 사람이 따로 봐야 한다 → **I-3**

---

## 5. 발견 사항

| ID | 심각도 | 요약 | 현재 결과(4 PASS / 5 FAIL)에 영향 |
|---|---|---|---|
| T-1 | 🟠 Medium | 대조군은 버그가 있어도 PASS — 증상 기반 검출만 있음 | 없음. 재현 목적엔 충분. 회귀 보호력은 약함 |
| T-2 | 🟠 Medium | Unit TB가 bypass 구조를 전제로 상류 handshake를 모델링 | 현재 DUT 결과는 유효. 다른 구조의 수정안에 재사용 시 오판 |
| T-3 | 🟡 Low | `[WVALID_READY_DEPENDENCY]` 메시지가 WAIT 시나리오 밖에서도 발생 가능 | 없음. 기존 runner 사용 시 혼동 가능 |
| T-4 | 🟡 Low | W-before-AW(주소보다 데이터가 먼저) 순서를 검증하지 않음 | 없음. 수정 RTL 검증 범위의 공백 |
| I-1 | ⚪ Info | CSR Slave 응답(B/R) backpressure 미검증 | 없음 |
| I-2 | ⚪ Info | AXI-Stream 경로 미지원 → 같은 유형 버그를 TB로 검출 불가 | 없음 (RTL 리뷰 R-1과 연결) |
| I-3 | ⚪ Info | Verilator 2-state: 리셋 중 X 미검증 / 기존 build 경고 62건 | 없음 |
| I-4 | ⚪ Info | `tb_drv`가 SCENARIO plusarg를 따로 파싱(`IMAGE_STREAM` 별칭 미정규화) | 없음 |

### T-1 (Medium) 대조군은 버그가 있어도 PASS한다

**무엇이 문제인가?**
`full_ready_first`, `full_fixed_stalls`는 원본(버그) RTL에서도 PASS다. Slave가 READY를 먼저 올리면, 버그가 있는 WVALID도 곧바로 따라 올라가서 겉보기엔 정상 전송이 되기 때문이다. 현재 checker는 "멈춤(증상)"만 보므로 Slave가 WVALID를 기다리는 시나리오에서만 버그를 잡는다.

**원인을 직접 잡는 방법**
이 DUT는 모든 flop이 상승 edge에서 바뀌는 동기 설계이고, TB는 입력(READY)을 하강 edge에서만 바꾼다. 따라서 **출력 WVALID가 하강 edge에서 바뀌었다면 입력→출력 조합 경로가 있다는 직접 증거**다.

| 시점 | TB 동작 | 원본 RTL의 WVALID | 수정 RTL의 WVALID |
|---|---|---|---|
| negedge | WREADY 0→1 | **같은 순간 0→1** ← 조합 의존 | 변화 없음 (이미 1) |
| posedge | handshake | 1 | 1 → (FIFO pop 후) posedge 직후에만 변함 |
| negedge | WREADY 1→0 | **데이터가 남아 있으면 같은 순간 1→0** | 변화 없음 |

권장 monitor (tb_top에 추가, runner의 TB 목록에도 추가):

```systemverilog
`timescale 1ns/1ps
// DUT 출력 WVALID가 clock 상승 edge가 아닌 시점에 바뀌면,
// 입력(WREADY 등)에서 출력으로 가는 조합 경로가 있다는 뜻이다.
// 전제: DUT는 posedge 동기 설계, TB는 negedge에서만 입력을 구동.
module tb_wvalid_comb_check(tb_if bus);
  always @(bus.m_wvalid_o) begin
    if (bus.aresetn === 1'b1 && bus.aclk === 1'b0)
      $fatal(1, "[WVALID_COMB_PATH] t=%0.3f WVALID=%b WREADY=%b : WVALID가 clock edge 없이 변함",
             $realtime, bus.m_wvalid_o, bus.m_wready_i);
  end
endmodule
```

기대 효과(시뮬레이션 미확인, 논리 추적 결과):
- 원본 RTL `full_fixed_stalls`: 데이터가 준비된 뒤 WREADY가 늦게 올라가는 구간이 있으므로(문서상 237 sample) 첫 stall 해제 시점에 FAIL.
- 원본 RTL `full_ready_first`: WREADY를 내릴 때 다음 데이터가 남아 있으면 FAIL. 타이밍에 따라 다르므로 실행으로 확인 필요.
- WAIT 시나리오: WREADY가 끝내 안 올라가므로 이 monitor는 반응하지 않는다. 대신 기존 정체 검사가 잡는다. **두 검사는 서로 보완**한다.
- 수정 RTL: WVALID는 flop 출력으로만 만들어지므로 FAIL하지 않아야 한다.

### T-2 (Medium) Unit TB가 bypass 구조를 전제로 작성됨

**무엇이 문제인가?**
상류 인터페이스의 계약은 "`atx_wdata_vld & atx_wdata_rdy`가 성립한 edge에서 한 beat 소비"다. 그런데 unit TB는 두 가지를 AXI 쪽 handshake 기준으로 처리한다.

1. `atx_wdata_vld`를 **AXI W handshake 이후**에만 내린다.
2. AXI handshake edge에서 `atx_wdata_rdy===1`을 검사한다.

현재 RTL(bypass)에서는 내부 소비와 AXI handshake가 같은 edge라서 문제가 없다. 하지만 출력에 register형 skid buffer를 넣는 수정안이라면 내부 소비가 먼저 일어난다. 그러면 같은 beat가 두 번 들어가거나(중복), 2번 검사가 거짓 FAIL을 낸다.

**권장 수정**: 상류 driver와 AXI 쪽 checker를 분리한다.

```systemverilog
// 상류 driver: 자기 handshake(atx_wdata_vld & atx_wdata_rdy)로만 진행
for (int n = 0; n < beats; n++) begin
  @(negedge clk); atx_wdata = pattern(n); atx_wdata_vld = 1;
  do @(posedge clk); while (atx_wdata_rdy !== 1'b1);   // 상류 handshake
end
@(negedge clk); atx_wdata_vld = 0;

// AXI 쪽 checker: W handshake마다 기대값과 비교 (beat 번호 기준)
always @(posedge clk) if (rst_n && m_wvalid_o === 1'b1 && m_wready_i === 1'b1) begin
  if (m_wdata_o !== pattern(axi_cnt) || m_wlast_o !== (axi_cnt == beats-1))
    $fatal(1, "[UNIT_DATA_FAIL] beat=%0d", axi_cnt);
  axi_cnt++;
end
```

> 기대값 큐(queue)를 두 always 블록에서 push/pop하면 같은 시각에 실행 순서 경쟁(race)이 생길 수 있다. 위처럼 beat 번호로 기대값을 계산하면 이 문제를 피할 수 있다.

### T-3 (Low) 의존성 FAIL 메시지가 WAIT 시나리오 밖에서도 발생 가능

`tb_wvalid_check`는 `tb_top`에 항상 연결되고, patch로 기존 `run_byte_tb.py`에도 포함됐다. 원본 RTL에서 READY-first 시나리오라도 `STALL_MAX`를 약 31 이상으로 주면, Slave가 WREADY를 32 cycle 이상 내리는 구간이 생긴다. 이때 `[WVALID_READY_DEPENDENCY] ... while Slave waited for WVALID`로 FAIL한다. 원본 RTL이 규칙을 어긴 것은 사실이지만, 실제로 Slave는 WVALID를 기다린 게 아니라 단순 stall 중이었으므로 **메시지가 상황과 다르다.** 기존에 PASS하던 회귀가 갑자기 FAIL로 바뀌는 효과도 있다.

```systemverilog
if (blocked_cycles >= limit_cycles) begin
  if (bus.scenario == "WREADY_WAIT_VALID" || bus.scenario == "WREADY_WAIT_VALID_MID")
    $fatal(1, "[WVALID_READY_DEPENDENCY] ready data/len pending while Slave waited for WVALID");
  else
    $fatal(1, "[WVALID_WITHHELD] data/len ready but WVALID low for %0d cycles during Slave stall",
           blocked_cycles);
end
```

### T-4 (Low) W-before-AW 순서를 검증하지 않음

AXI4에서는 W 데이터가 AW 주소보다 먼저 올 수 있고, Slave가 W를 먼저 받아도 된다. 수정 RTL은 데이터가 준비되면 AW handshake 전에도 WVALID를 올릴 수 있다. 그런데 현재 TB는:
- Slave가 AW mailbox를 받은 뒤에만 W를 처리하고,
- scoreboard가 `[SB] W accepted without AW`로 이를 금지한다.

따라서 "W를 먼저 받아도 데이터 순서가 맞는가"는 검증되지 않는다. `WREADY_BEFORE_AW` 시나리오를 추가하고, scoreboard가 W beat를 임시 큐에 보관했다가 AW가 오면 매칭하도록 확장할 것을 권장한다.

### I-1 ~ I-4 (Info)

- **I-1**: `s_bready_i`, `s_rready_i`가 1로 고정되어 CSR Slave 쪽 B/R 응답의 backpressure와 VALID/READY 의존성은 검증되지 않는다.
- **I-2**: TB가 AXI4→AXI4만 지원한다(`[DRV]`, `[SEQ]`에서 $fatal). 같은 유형의 버그가 AXI-Stream 출력 모듈에 있지만 이 TB로는 검출할 수 없다. (RTL 리뷰 R-1)
- **I-3**: Verilator는 2-state 시뮬레이터다. 리셋 중 X 전파, 리셋 직후 VALID 값은 검증되지 않았다. 기존 build 경고(full 62건, unit 1건)는 `-Wno-fatal` 때문에 build를 막지 않으므로 width 경고 등은 따로 검토가 필요하다.
- **I-4**: `tb_drv`는 `+SCENARIO`를 독립적으로 읽는다. 같은 time 0의 initial 블록 순서에 의존하지 않으려는 선택으로 보이며, `IMAGE_STREAM` 별칭은 `tb_seq`에서만 정규화된다. 새 시나리오 이름 비교에는 영향이 없다.

---

## 6. 신입 교육 포인트

1. **"PASS = 버그 없음"이 아니다.** READY를 먼저 주는 Slave만으로는 규칙 1 위반을 절대 못 찾는다. Slave 정책을 바꿔 봐야 숨은 버그가 드러난다.
2. **증상 검출 vs 원인 검출.** 32-cycle 정체 검사는 증상(멈춤)을, negedge 변화 monitor는 원인(조합 경로)을 본다. 좋은 TB는 둘을 같이 쓴다.
3. **TB 입력은 negedge에서 구동한다.** posedge 샘플링과 경쟁(race)을 피하고, TB가 조합 루프를 만들지 않게 한다.
4. **내부 신호는 보기만 한다.** force/release로 DUT 내부를 바꾸면 "TB가 만든 결과"와 "DUT 결과"를 구분할 수 없게 된다.
5. **Directed test는 범위를 문서에 적는다.** 이번 TB는 검증하지 않은 범위(AXIS, ROB, X, reset 중 stall)를 명시했다. 좋은 습관이다.

---

## 7. 권장 조치 (우선순위)

| 순위 | 조치 | 확인 방법 |
|---|---|---|
| 1 | T-1 monitor 추가 | 원본 RTL에서 `full_fixed_stalls`가 `[WVALID_COMB_PATH]`로 FAIL, 수정 RTL에서 9/9 PASS 유지 |
| 2 | T-2 unit TB 상류/AXI 분리 | 원본·수정 RTL 결과 변동 없음 확인 |
| 3 | T-4 `WREADY_BEFORE_AW` 시나리오 | 수정 RTL에서 데이터/predictor PASS |
| 4 | T-3 메시지 분리 | `run_byte_tb.py --stall-max 40`으로 원본 RTL 실행 시 `[WVALID_WITHHELD]` 출력 확인 |
| 5 | AXIS 경로 TB 지원 | RTL 리뷰 R-1 수정안 검증용 |

---

## 부록 A. 검토한 파일

**Drive TB 폴더 (zip 제외 18개)**: `README_WVALID_READY.md`, `TB_CHANGES.patch`, `SOURCE_MANIFEST.json`, `run_wvalid_regression.py`, `run_byte_tb.py`, `tb_wvalid_check.sv`, `tb_wvalid_unit.sv`, `tb_top.sv`, `tb_drv.sv`, `tb_seq.sv`, `tb_sb.sv`, `tb_monitor.sv`, `tb_if.sv`, `tb_var.sv`, `tb_duv.sv`, `tb_dpi.sv`, `tb_ref.cpp`, `axi_dma_tb.sv`

**상위 폴더**: `BUG_AXI_WVALID_DEPENDS_ON_WREADY.md`, `README_WVALID_READY.md`

**컨텍스트(교육TF 프로젝트) 대조 파일**: `adma_dm_axi_w.sv`, `adma_dm_wr_host.sv`, `adma_data_mover.sv`, `axi_dma.sv`, `adma_dm_data_buf.sv`, `skid_buffer.v`, `sync_fifo.v`, `tb_top.sv`, `tb_drv.sv`, `tb_seq.sv`, `tb_sb.sv`, `tb_monitor.sv`, `tb_if.sv`, `tb_var.sv`, `tb_duv.sv`, `axi_dma_tb.sv`

**참고 규격**: Arm AMBA AXI and ACE Protocol Specification (IHI 0022E/H) A3.2.1, A3.3.1 — handshake 및 channel dependency 규칙
