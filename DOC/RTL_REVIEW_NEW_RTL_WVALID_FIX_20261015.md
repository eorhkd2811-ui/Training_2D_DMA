# RTL 수정 검토 보고서 — 수정 RTL (BUG-AXI-W-001 수정본)

> 경로 정리 (2026-10-16): 아래 검증·검토 결과는 과거 기록이며 이번 문서 정리에서 재실행하지 않았다. 당시 원본 로그와 manifest는 현재 저장소에 포함되어 있지 않다. 기준 RTL은 `main`, 수정 RTL과 WVALID 검증 TB는 `feature/wvalid-fix`에 있다. 명령은 저장소 최상위에서 실행한다.

| 항목 | 내용 |
|---|---|
| 검토일 | 2026-10-15 (Asia/Seoul) |
| 검토 대상 | `RTL/` (`feature/wvalid-fix`) — HDL 42개(`.sv` 25 + `common/` `.v` 17), 브랜치 diff, `RTL_AXI_WVALID_FIX_CHANGELOG_KO.md`, 과거 검증 요약 |
| 기준 RTL | 교육TF 프로젝트(현재 컨텍스트)의 RTL = 수정 전 RTL |
| 관련 버그 | BUG-AXI-W-001: WVALID가 WREADY에 의존하여 합법적인 Slave와 deadlock |
| 검토 방법 | 정적 코드 리뷰(파일 대조 + 논리 추적). **이번 검토에서 시뮬레이션은 직접 실행하지 않았다.** 회귀 결과(수정 전 4/9, 수정 후 9/9 PASS)는 작성자의 과거 검증 요약을 인용했다. |
| 결론 | **AXI4 W 채널 수정은 정확하다(승인 가능).** 단, **같은 원인의 버그가 AXI-Stream 출력 모듈 `adma_dm_dst_axis.sv`에 그대로 남아 있다(R-1).** R-1은 범위 외(AXIS)이므로 수정하지 않고 기록만 한다. |
| 범위 결정 (2026-10-16) | 이번 실습은 AXI4 구성(`SRC_IF_TYPE = DST_IF_TYPE = "AXI4"`)만 사용한다. AXI4-Stream(AXIS) 경로의 버그는 **범위 외(AXIS)**로 표시하고 수정·검증하지 않는다. 원인과 수정안은 기록으로만 남긴다. |

---

## 1. 한눈에 보는 결론

- ✅ 변경 파일은 `adma_dm_axi_w.sv` 1개, 기능 코드 1행. 버그 원인을 정확히 겨냥했다.
- ✅ WVALID가 더 이상 WREADY에 의존하지 않는다. 데이터 소비·카운터·길이 FIFO pop은 기존대로 handshake에서만 일어난다.
- ✅ stall 중 WVALID/WDATA/WLAST가 유지된다. (근거: FIFO 구조, 4장)
- ✅ 포트·파라미터·내부 신호명이 바뀌지 않아 기존 TB(probe, unit TB `.*`)와 호환된다.
- ⚪ **R-1 (범위 외(AXIS), 수정하지 않음)**: `adma_dm_dst_axis.sv`에 `TVALID`가 `TREADY`에 의존하는 같은 패턴이 남아 있다. AXIS 구성을 쓴다면 High에 해당한다.
- 🟡 **R-2 (Low)**: 리셋 직후 WVALID를 가려 주던 `& WREADY`가 사라졌다. 4-state 시뮬레이션으로 리셋 동작 확인을 권장한다.
- ⚪ R-3 ~ R-5: W-before-AW 가능, 모듈 계약 assertion, 타이밍 개선 (Info)

---

## 2. 변경 범위 확인

### 2.1 무엇이 바뀌었나?

수정 RTL의 HDL 42개를 수정 전 RTL manifest(과거 소스 목록)의 파일 크기와 대조했다.

| 구분 | 파일 수 | 결과 |
|---|---:|---|
| `adma_*.sv`, `axi_dma.sv` | 25 | 24개 크기 동일, **`adma_dm_axi_w.sv`만 3162 → 3302 bytes** |
| `common/*.v` | 17 | 17개 모두 크기 동일 |
| 합계 | 42 | 변경 1개 — 브랜치 diff, 과거 검증 요약(`changed_source_files`)과 일치 |

> 크기 일치는 "내용 동일"의 강한 근거지만 증명은 아니다. SHA-256은 이번 검토에서 재계산하지 않았고, 작성자 manifest를 근거로 했다. 전체 목록은 부록 A.

### 2.2 기준 RTL이 컨텍스트와 같은가?

브랜치 diff의 context 행(73~79행)과 컨텍스트 `adma_dm_axi_w.sv` 73~79행이 같다. 또한 버그 문서의 원인 행(40행 `SBUF_TYPE=4`, 75~77행)도 컨텍스트 파일과 일치한다. → **수정본은 컨텍스트 RTL을 기준으로 만들어졌다.**

### 2.3 실제 diff

```diff
  assign m_wdata  = atx_wdata;
  assign m_wlast  = ~|(wdata_cnt^wdata_len);
  assign db_hsk   = atx_wdata_vld & atx_wdata_rdy;
- assign m_wvalid = atx_wdata_vld & atx_wdata_rdy;
+ // Present a beat when both data and burst length are available.
+ // VALID must not depend on READY; only db_hsk consumes the beat.
+ assign m_wvalid = atx_wdata_vld & wdata_len_vld;
  assign atx_wdata_rdy = m_wready & wdata_len_vld;
```

그 외에는 파일 끝 개행만 추가됐다. 변경 내역 문서의 설명("기능 1행, 주석 2행, 개행 정리", "수정 assign은 78행")과 일치한다.

---

## 3. 수정 내용 분석

### 3.1 식으로 보기

`w_sb`가 bypass(`SBUF_TYPE=4`)이므로 `m_wvalid_o = m_wvalid`, `m_wready = m_wready_i`다. 이를 대입하면:

```text
[수정 전]  WVALID = atx_wdata_vld & wdata_len_vld & WREADY      ← 출력 VALID 식에 입력 READY 포함
[수정 후]  WVALID = atx_wdata_vld & wdata_len_vld               ← READY 없음

           db_hsk = atx_wdata_vld & atx_wdata_rdy
                  = atx_wdata_vld & wdata_len_vld & WREADY
                  = WVALID & WREADY                             ← AXI W handshake와 정확히 같은 사건
```

**핵심**: 수정 후 "VALID(준비됨, 상태)"와 "db_hsk(전송됨, 사건)"가 분리됐다. 그리고 bypass 구조이기 때문에 내부 소비 시점(`db_hsk`)과 AXI handshake 시점이 정확히 같다.

### 3.2 신호 흐름 그림

```text
 data FIFO (adma_dm_data_buf) ── atx_wdata_vld ──┐
                                                  AND ──► m_wvalid ──(bypass)──► WVALID (출력)
 길이 FIFO (atx_buffer)        ── wdata_len_vld ──┘

 WREADY (입력) ──(bypass)──► m_wready ──AND(wdata_len_vld)──► atx_wdata_rdy ──► data FIFO pop
                                                            └──► db_hsk ──► wdata_cnt 증가
                                                                        └─► (WLAST면) 길이 FIFO pop

 [수정 전] atx_wdata_rdy ──► m_wvalid 로 가는 선이 하나 더 있었다.
           = 입력 WREADY에서 출력 WVALID로 가는 조합 경로 → 규칙 위반의 정체
```

### 3.3 진리표

| data valid | length valid | WREADY | 수정 전 WVALID | 수정 후 WVALID | 이번 edge에 소비 |
|:-:|:-:|:-:|:-:|:-:|:-:|
| 0 | x | x | 0 | 0 | 없음 |
| 1 | 0 | x | 0 | 0 | 없음 |
| 1 | 1 | 0 | 0 | **1** | 없음 — 같은 beat 유지 |
| 1 | 1 | 1 | 1 | 1 | 1 beat 소비 |

`wdata_len_vld`를 VALID 조건에 남긴 것은 옳다. 길이 정보가 없으면 WLAST를 계산할 수 없기 때문이다.

---

## 4. AXI 규칙 체크리스트

| # | 규칙 (IHI 0022, A3.2.1 / A3.3.1 / A3.1.2) | 근거 (코드) | 결과 |
|---|---|---|---|
| 1 | Master는 READY를 기다려 VALID를 올리면 안 된다 | 수정 식에 `m_wready_i`가 없다. 입력은 FIFO 포인터(flop) 기반 신호뿐이다 | ✅ |
| 2 | VALID를 올렸으면 handshake 전에 내리면 안 된다 | WREADY=0 → `db_hsk=0` → data FIFO `rd_ptr` 고정 → `atx_wdata_vld` 유지. 길이 FIFO pop 조건 `m_wlast & db_hsk`=0 → `wdata_len_vld` 유지 | ✅ |
| 3 | handshake 전 payload(WDATA/WLAST)가 바뀌면 안 된다 | WDATA = data FIFO head `mem[rd_ptr]`. `sync_fifo`(NORMAL)는 full이 아닐 때만 쓰므로, 비어 있지 않은 동안 쓰기 위치 ≠ head. WLAST = f(`wdata_cnt`, `wdata_len`)이고 둘 다 `db_hsk` 때만 변한다 | ✅ |
| 4 | WLAST는 burst 마지막 beat에서만 1 | 식 변경 없음 | ✅ |
| 5 | 리셋 중 Master는 WVALID를 Low로 구동 | FIFO 포인터가 **동기 리셋** → 리셋 중 첫 상승 edge 전에는 값이 정해지지 않음 | ⚠️ R-2 |
| 6 | 데이터 순서 = 주소 순서 | AW FIFO와 W 길이 FIFO가 같은 `atx_vld_flt`로 동시에 push됨 (`adma_dm_wr_host`) | ✅ |

---

## 5. 발견 사항

| ID | 심각도 | 요약 |
|---|---|---|
| R-1 | ⚪ 범위 외(AXIS) — 수정하지 않음 (AXIS 구성 사용 시 High, AXI4 구성에는 영향 없음) | `adma_dm_dst_axis.sv`: TVALID가 TREADY에 의존 — 기록만 유지 |
| R-2 | 🟡 Low | 리셋 직후 WVALID 마스킹 제거 → 4-state 리셋 확인 권장 |
| R-3 | ⚪ Info | WVALID가 AW handshake보다 먼저 나갈 수 있음 (AXI4 합법) |
| R-4 | ⚪ Info | 모듈 계약(상류 hold)을 assertion으로 문서화 권장 |
| R-5 | ⚪ Info | 입력→출력 조합 경로 제거로 타이밍 개선, 면적 변화 없음 |

### R-1 [범위 외(AXIS)] `adma_dm_dst_axis.sv`에 같은 패턴이 남아 있다

> **범위 외(AXIS), 수정하지 않음.** 이번 실습은 AXI4 구성만 사용한다(2026-10-16 결정). 아래 원인과 권장 수정은 기록용으로 남긴다. AXIS 구성을 사용하게 되면 이 항목을 다시 High로 검토한다.

컨텍스트 사본 기준 101~102행 (수정 RTL 사본도 크기 4870 bytes로 원본과 동일 = 미수정):

```systemverilog
assign m_tvalid      = atx_wdata_vld & atx_wdata_rdy;   // 101행
assign atx_wdata_rdy = m_tready & cur_atx_vld;          // 102행
```

62행의 `axis_sb`도 `SBUF_TYPE=4`(bypass)이므로:

```text
TVALID = atx_wdata_vld & cur_atx_vld & TREADY       ← W 채널 원본 버그와 똑같은 구조
```

AMBA AXI4-Stream 규격(IHI 0051A, Handshake process)도 "송신측은 TREADY를 기다려 TVALID를 올리면 안 된다"고 정한다. TREADY를 TVALID 확인 후 올리는 수신측과 연결하면 **똑같은 deadlock**이 생긴다.

현재 회귀는 `DST_IF_TYPE="AXI4"` 전용이라 이 경로를 실행하지 않는다(TB 리뷰 I-2). 그래서 9/9 PASS와 무관하게 남아 있다.

**권장 수정** (W 채널과 같은 방식):

```systemverilog
// TVALID는 데이터와 전송 정보(TLAST 계산용 길이)가 준비되면 READY와 무관하게 올린다.
assign m_tvalid      = atx_wdata_vld & cur_atx_vld;
assign atx_wdata_rdy = m_tready & cur_atx_vld;          // 변경 없음
assign m_axis_hsk    = m_tvalid & m_tready;             // 변경 없음: 소비/카운터/atx_done은 handshake 기준
```

수정 후에도 `m_axis_hsk = atx_wdata_vld & cur_atx_vld & TREADY`로 기존과 같으므로 `tdata_cnt`, 길이 FIFO pop, `atx_done` 동작은 바뀌지 않는다.

> 참고(기존 동작): `m_tid = atx_id[cur_chn_id]`는 CSR 레지스터 값을 직접 쓴다. 전송 중 소프트웨어가 해당 채널의 `ATX_ID` CSR을 바꾸면 stall 중 TID가 바뀔 수 있다. 소프트웨어 사용 제약으로 문서화하는 것을 권장한다.

### R-2 (Low) 리셋 직후 WVALID 마스킹이 사라졌다

- 수정 전: `WVALID = ... & WREADY`. 리셋 중 Slave가 WREADY를 0으로 두면, FIFO 포인터가 아직 정해지지 않아도 WVALID는 0이었다.
- 수정 후: `WVALID = atx_wdata_vld & wdata_len_vld`. 두 신호 모두 `sync_fifo`(NORMAL)의 포인터에서 나오고, 이 포인터는 **동기 리셋**(`always @(posedge clk) if(!rst_n)`)이다. 따라서 리셋 중 **첫 상승 edge 전**에는 WVALID가 정해지지 않는다(4-state에서는 X).

AXI는 리셋 중 Master가 WVALID를 Low로 구동하도록 요구한다(A3.1.2). 보통은 리셋 동안 clock이 돌기 때문에 첫 edge 이후 0이 되어 문제가 없다. AW/AR 채널(`skid_buffer` SBUF_TYPE 0)도 이미 같은 동기 리셋 방식이므로 **설계 전체의 관례**이며 이번 수정이 새 유형을 만든 것은 아니다. 다만 W 채널은 이전에 우연히 가려져 있었으므로 다음을 권장한다.

1. SoC 리셋 사양에서 "리셋 중 clock 동작(최소 1 cycle 이상)"이 보장되는지 확인한다.
2. 4-state 시뮬레이터(VCS, Xcelium 등)에서 다음 assertion으로 확인한다.

```systemverilog
// 리셋 중 두 번째 상승 edge부터 WVALID는 반드시 0
assert property (@(posedge aclk) !aresetn && $past(!aresetn) |-> m_wvalid_o === 1'b0);
```

### R-3 (Info) WVALID가 AW보다 먼저 나갈 수 있다

수정 전에는 Slave가 WREADY를 올려야만 WVALID가 나왔으므로, 사실상 W가 AW보다 앞설 수 없었다. 수정 후에는 데이터가 준비되면 AW handshake 전에도 WVALID가 나간다. **AXI4에서는 합법**이며, AW FIFO와 W 길이 FIFO가 같은 순서로 채워지므로 데이터 순서도 맞다(4장 #6). 다만 연결할 interconnect/Slave가 이를 지원하는지 시스템 레벨에서 확인하고, TB에 W-before-AW 시나리오를 추가할 것을 권장한다(TB 리뷰 T-4).

### R-4 (Info) 모듈 계약을 assertion으로 남기자

이 수정의 정확성은 "상류(data FIFO)가 소비 전까지 VALID와 데이터를 유지한다"는 계약에 기대고 있다. 변경 내역 문서도 이를 명시했다. 다음 assertion을 RTL에 넣어 두면, 나중에 상류 구조가 바뀌어도 바로 발견할 수 있다.

```systemverilog
`ifndef SYNTHESIS
// 상류 계약: 소비(atx_wdata_rdy)되기 전에는 VALID와 데이터를 유지해야 한다
a_upstream_hold: assert property (@(posedge clk) disable iff (!rst_n)
    atx_wdata_vld && !atx_wdata_rdy |=> atx_wdata_vld && $stable(atx_wdata));
// AXI 규칙: stall된 WVALID와 payload는 handshake까지 유지
a_wvalid_hold: assert property (@(posedge clk) disable iff (!rst_n)
    m_wvalid_o && !m_wready_i |=> m_wvalid_o && $stable({m_wdata_o, m_wlast_o}));
`endif
```

> Verilator의 concurrent assertion 지원 범위는 버전마다 다르므로 사용 전 확인한다.

### R-5 (Info) 타이밍과 면적

- **좋아진 점**: 입력 `m_wready_i` → 출력 `m_wvalid_o` 조합 경로가 없어졌다. 출력 VALID가 flop 기반이 되어 I/O 타이밍에 유리하다.
- **남은 경로**: `m_wready_i` → `atx_wdata_rdy` → data FIFO pop은 READY 전파 경로로 기존과 같다(규칙 위반 아님).
- 새 flop이나 FIFO 단은 추가되지 않았다. 합성·STA는 수행되지 않았다(변경 내역 문서 명시).

---

## 6. 같은 패턴 전수 점검: "VALID 식에 READY가 들어 있는가?"

| 모듈 | 출력 VALID / 역할 | 생성 방식 | READY 의존 | 판정 |
|---|---|---|---|---|
| `adma_dm_axi_w` | WVALID | `atx_wdata_vld & wdata_len_vld` (수정 후) | 없음 | ✅ 수정됨 |
| `adma_dm_dst_axis` | TVALID | `atx_wdata_vld & atx_wdata_rdy`, bypass | **있음** | ⚪ R-1 범위 외(AXIS) |
| `adma_dm_axi_ax` (AW/AR) | AWVALID/ARVALID | `skid_buffer` SBUF_TYPE 0 (`fwd_valid_q` flop) | 없음 | ✅ |
| `adma_dm_axi_r` | RREADY 출력 (수신측) | READY는 VALID에 의존해도 됨 | 해당 없음 | ✅ |
| `adma_dm_axi_b` | BREADY 출력 (수신측) | ROB 미사용 시 상수 1 | 해당 없음 | ✅ |
| `adma_dm_src_axis` | TREADY 출력 (수신측) | READY 경로 | 해당 없음 | ✅ |
| `axi4_ctrl` (CSR Slave) | BVALID / RVALID | `skid_buffer` SBUF_TYPE 2/5 (flop 기반) | 없음 | ✅ |
| `adma_dm_data_buf` (내부) | `dst_vld` | `sync_fifo` NORMAL `~empty` (flop 기반) | 없음 | ✅ |

> 검색 팁: 같은 버그는 복사·붙여넣기로 퍼지기 쉽다. RTL 전체에서 `valid.*=.*rdy`, `valid.*=.*ready` 패턴을 grep하고, 그 모듈이 bypass skid buffer를 쓰는지 함께 확인한다.

---

## 7. 추가 검증 권장

| 순위 | 항목 | 이유 |
|---|---|---|
| — | ~~R-1 수정 + AXIS directed test~~ | 범위 외(AXIS) — 수행하지 않음 (2026-10-16 결정) |
| 2 | TB 리뷰 T-1의 조합 경로 monitor로 9개 시험 재실행 | READY-first 대조군에서도 원인을 직접 검출 |
| 3 | 4-state 시뮬레이션 리셋 검사 (R-2) | Verilator 2-state로는 확인 불가 |
| 4 | W-before-AW 시나리오 (R-3, TB T-4) | 수정 후 새로 가능해진 순서 |
| 5 | 경계 조건: 256-beat burst, outstanding FIFO 가득 참, 마지막 beat(WLAST)에서 긴 stall, burst 연속 전송 | 현재 directed test는 최대 8-beat, 2 outstanding |

---

## 8. 신입 교육 포인트

1. **VALID는 "상태", handshake는 "사건"이다.** 원본 버그는 둘을 같은 식으로 만든 데서 시작됐다. 수정은 둘을 분리한 것이다.
2. **bypass skid buffer는 선 한 가닥이다.** 레지스터가 없으므로 출력 VALID가 내부 조합 논리에 그대로 붙는다. bypass를 쓸 때는 VALID 식에 READY가 들어가지 않았는지 반드시 본다.
3. **수정은 작게, 점검은 넓게.** 이번 수정이 1행으로 끝난 것은 좋다(위험 최소). 하지만 같은 패턴이 다른 모듈에 있는지 전수 점검하는 것까지가 수정 작업이다(R-1). 점검에서 찾은 버그가 실습 범위 밖이면 수정 대신 범위 외로 기록한다.
4. **"9/9 PASS"의 범위를 읽는다.** 작성자도 명시했듯 이 결과는 선택된 9개 시험의 결과이며, 실행되지 않은 구성(AXIS 등)에 대해서는 아무것도 말해 주지 않는다.

---

## 부록 A. 파일 대조표 (수정 전 RTL manifest 크기 vs 수정 RTL 크기, bytes)

| 파일 | 원본 | 수정 RTL | 변경 |
|---|---:|---:|:-:|
| adma_address_adapter.sv | 2172 | 2172 | |
| adma_as_atx_arb.sv | 3754 | 3754 | |
| adma_as_atx_fetch.sv | 7168 | 7168 | |
| adma_as_atx_req.sv | 3911 | 3911 | |
| adma_as_tx_stat.sv | 3042 | 3042 | |
| adma_atx_sched.sv | 6700 | 6700 | |
| adma_chn_man.sv | 4531 | 4531 | |
| adma_cm_chn_unit.sv | 4687 | 4687 | |
| adma_cm_tf_split.sv | 7701 | 7701 | |
| adma_cm_tx_fetch.sv | 5098 | 5098 | |
| adma_cm_xfer_stat.sv | 1617 | 1617 | |
| adma_data_mover.sv | 9175 | 9175 | |
| adma_desc_queue.sv | 6166 | 6166 | |
| adma_dm_axi_ax.sv | 2771 | 2771 | |
| adma_dm_axi_b.sv | 5406 | 5406 | |
| adma_dm_axi_r.sv | 6104 | 6104 | |
| **adma_dm_axi_w.sv** | **3162** | **3302** | **★** |
| adma_dm_data_buf.sv | 1413 | 1413 | |
| adma_dm_dst_axis.sv | 4870 | 4870 | (R-1, 범위 외(AXIS), 수정하지 않음) |
| adma_dm_rd_host.sv | 6322 | 6322 | |
| adma_dm_src_axis.sv | 4381 | 4381 | |
| adma_dm_wr_host.sv | 7443 | 7443 | |
| adma_reg_map.sv | 12744 | 12744 | |
| adma_reg_wrapper.sv | 22940 | 22940 | |
| axi_dma.sv | 22399 | 22399 | |
| common/adapter/axi/axi4_ctrl.v | 32206 | 32206 | |
| common/arbiter/iwrr/arb_prior_granter.v | 1921 | 1921 | |
| common/arbiter/iwrr/arb_round_comp_detector.v | 1532 | 1532 | |
| common/arbiter/iwrr/arbiter_iwrr_1cycle.v | 5802 | 5802 | |
| common/converter/bin2gray_converter.v | 564 | 564 | |
| common/converter/gray2bin_converter.v | 563 | 563 | |
| common/decoder/onehot_decoder/onehot_decoder.v | 419 | 419 | |
| common/edgedet/edgedet.v | 561 | 561 | |
| common/encoder/onehot_encoder/onehot_encoder.v | 1260 | 1260 | |
| common/fifo/async_fifo/asyn_fifo.v | 16425 | 16425 | |
| common/fifo/sync_fifo/fifo.v | 3217 | 3217 | |
| common/fifo/sync_fifo/sync_fifo.v | 12710 | 12710 | |
| common/memory/mem.v | 1512 | 1512 | |
| common/reorder_buffer/reorder_buffer.v | 5905 | 5905 | |
| common/skid_buffer/sb_fifo.v | 2248 | 2248 | |
| common/skid_buffer/skid_buffer.v | 14024 | 14024 | |
| common/splitter/splitter.v | 1508 | 1508 | |

## 부록 B. 검토 근거 파일

- 수정 RTL: `adma_dm_axi_w.sv`(수정본 전체), 브랜치 diff, `RTL_AXI_WVALID_FIX_CHANGELOG_KO.md`, 과거 검증 요약, 폴더 내 전체 HDL 파일 목록/크기
- 컨텍스트(교육TF 프로젝트): `adma_dm_axi_w.sv`, `adma_dm_dst_axis.sv`, `adma_dm_axi_ax.sv`, `adma_dm_axi_r.sv`, `adma_dm_axi_b.sv`, `adma_dm_src_axis.sv`, `adma_dm_data_buf.sv`, `adma_dm_wr_host.sv`, `adma_data_mover.sv`, `axi_dma.sv`, `skid_buffer.v`, `sync_fifo.v`, `axi4_ctrl.v`
- 규격: Arm AMBA AXI and ACE Protocol Specification (IHI 0022E/H) A3.1.2, A3.2.1, A3.3.1 / AMBA AXI4-Stream Protocol Specification (IHI 0051A) Handshake process

