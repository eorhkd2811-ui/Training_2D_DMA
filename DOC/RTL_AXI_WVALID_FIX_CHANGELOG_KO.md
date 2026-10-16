# AXI WVALID / WREADY 의존성 수정 — 개발자 변경 내역

> 경로 정리 (2026-10-16): 아래 검증·검토 결과는 과거 기록이며 이번 문서 정리에서 재실행하지 않았다. 당시 원본 로그와 manifest는 현재 저장소에 포함되어 있지 않다. 기준 RTL은 `main`, 수정 RTL과 WVALID 검증 TB는 `feature/wvalid-fix`에 있다. 명령은 저장소 최상위에서 실행한다.

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-14, Asia/Seoul |
| 관련 Bug | `BUG-AXI-W-001`: WVALID가 WREADY에 의존하여 deadlock 발생 |
| 상태 | **수정본 작성 및 기존 재현 regression 9/9 PASS** |
| 기준 소스 | `main`의 `RTL/` — RTL/common HDL 42개 |
| 저장 위치 | `feature/wvalid-fix` 브랜치의 `RTL/` |
| 수정 파일 | `adma_dm_axi_w.sv` 1개; 기능 코드 1행 변경, 설명 주석 2행 추가, 파일 끝 개행 정리 |
| 원본 보존 | 기존 재현 manifest와 원본 HDL 42개 SHA-256 일치. 실행 전후 원본 SHA-256 일치 |

## 1. 어떤 문제를 해결했는가?

DMA Master에 보낼 데이터가 있어도 Slave의 `WREADY`가 0이면 `WVALID`를 올리지 못했다. Slave가 “Master의 WVALID를 보고 나서 WREADY를 올리겠다”는 합법적인 방식으로 동작하면 양쪽 모두 기다려 전송이 멈췄다. 이를 **deadlock**이라고 한다.

이번에는 **데이터와 burst 길이가 준비되면 WREADY와 관계없이 WVALID를 먼저 제시하도록** 수정했다. 실제 데이터를 다음 beat로 넘기는 시점은 기존대로 handshake가 성립할 때다.

기존 보고서: [BUG_AXI_WVALID_DEPENDS_ON_WREADY.md](BUG_AXI_WVALID_DEPENDS_ON_WREADY.md).

## 2. 처음 읽는 엔지니어를 위한 용어

| 용어 / 신호 | 이 코드에서의 의미 |
|---|---|
| beat | 한 번의 handshake로 전송하는 데이터. 이번 검증은 256 bits = 32 bytes |
| burst | 연속된 여러 beat를 하나의 transaction으로 묶은 것 |
| `WVALID` | Master가 “현재 WDATA와 WLAST가 유효하다”고 알리는 신호 |
| `WREADY` | Slave가 “현재 데이터를 받을 수 있다”고 알리는 신호 |
| handshake | clock 상승 edge에서 VALID와 READY가 모두 1인 상태. 이때 한 beat가 전송됨 |
| stall / backpressure | 수신 측이 READY를 0으로 내려 전송을 기다리게 하는 상태 |
| `atx_wdata_vld` | 내부 data FIFO에 내보낼 데이터가 있다는 표시 |
| `wdata_len_vld` | 현재 burst 길이가 metadata FIFO에 있다는 표시 |
| `wdata_len` | AXI AWLEN 값. 예: 4-beat burst의 AWLEN은 3 |
| `wdata_cnt` | 현재 burst에서 이미 소비한 beat 수. 0부터 시작 |
| `db_hsk` | 내부 data FIFO에서 현재 beat를 실제로 소비하는 조건 |

**VALID는 “준비됐다”는 표시이고, handshake는 “전송했다”는 사건이다.** 두 조건을 구분하는 것이 이번 수정의 핵심이다.

## 3. 수정 전 코드가 멈추는 이유

기준 파일의 75~77행은 다음과 같다.

```systemverilog
assign db_hsk   = atx_wdata_vld & atx_wdata_rdy;
assign m_wvalid = atx_wdata_vld & atx_wdata_rdy;
assign atx_wdata_rdy = m_wready & wdata_len_vld;
```

`w_sb`는 `SBUF_TYPE=4`, 즉 bypass 구성이다. 따라서 `m_wready`는 외부 `m_wready_i`를 그대로 받고, 내부 `m_wvalid`는 외부 `m_wvalid_o`로 그대로 나간다. 위 식을 합치면 아래 관계가 된다.

```text
WVALID = data_valid AND length_valid AND WREADY
```

데이터와 길이 정보가 모두 준비됐더라도 WREADY가 0이면 WVALID는 반드시 0이다. Slave가 WVALID를 기다리는 경우 이 조건이 계속 유지된다. 기존 구현은 WVALID를 handshake 조건과 같게 만들었기 때문에 문제가 발생했다.

## 4. 실제 변경 내용

```diff
     assign db_hsk   = atx_wdata_vld & atx_wdata_rdy;
-    assign m_wvalid = atx_wdata_vld & atx_wdata_rdy;
+    // Present a beat when both data and burst length are available.
+    // VALID must not depend on READY; only db_hsk consumes the beat.
+    assign m_wvalid = atx_wdata_vld & wdata_len_vld;
     assign atx_wdata_rdy = m_wready & wdata_len_vld;
```

수정본의 해당 assign은 78행이다. 새 동작은 다음과 같다.

```text
WVALID = data_valid AND length_valid
data_consumed = data_valid AND length_valid AND WREADY
```

| data valid | length valid | WREADY | 수정 전 WVALID | 수정 후 WVALID | 데이터 소비 |
|---:|---:|---:|---:|---:|---:|
| 0 | 1 | 0 또는 1 | 0 | 0 | 없음 |
| 1 | 0 | 0 또는 1 | 0 | 0 | 없음 |
| 1 | 1 | 0 | 0 | **1** | 없음 — 같은 beat를 유지 |
| 1 | 1 | 1 | 1 | 1 | 한 beat 소비 |

`wdata_len_vld`를 남겨 둔 이유는 WLAST를 계산할 현재 burst 길이가 필요하기 때문이다. 단순히 `m_wvalid = atx_wdata_vld`로 바꾸면 길이 정보가 없는 상태에서도 데이터를 유효하다고 표시할 수 있다.

## 5. READY가 낮은 동안 무엇이 유지되는가?

현재 bypass 구성에서는 다음 조건이 유지된다.

1. `WREADY=0`이면 `atx_wdata_rdy=0`이므로 `db_hsk=0`이다.
2. data FIFO가 현재 데이터를 소비하지 않는다. 현재 정상 FIFO는 read pointer가 이동하지 않는 동안 같은 head 데이터를 제공한다.
3. `wdata_cnt`는 `db_hsk`일 때만 갱신되므로 stall 중에는 바뀌지 않는다.
4. 길이 FIFO의 pop 조건은 `m_wlast & db_hsk`다. 마지막 beat여도 handshake 전에는 현재 길이를 제거하지 않는다.
5. 따라서 WVALID, WDATA, WLAST를 유지하다가 WREADY가 1인 edge에서 같은 beat를 전송한다.

이 설명은 upstream이 VALID/payload를 수락 전까지 유지한다는 전제에 따른다. 전체 DMA에서는 실제 `adma_dm_data_buf`의 FIFO 경로로, unit TB에서는 같은 규칙을 지키는 stimulus로 검증했다. 단독 모듈에 잘못된 upstream 입력을 주었을 때까지 보호하는 추가 저장 장치를 넣은 것은 아니다.

예를 들어 4-beat burst의 마지막 beat에서는 `wdata_cnt=3`, `wdata_len=3`, `WLAST=1`이다. 이때 WREADY가 0이면 마지막 beat를 유지한다. WREADY가 1이 된 edge에서만 마지막 데이터를 소비하고, counter를 0으로 되돌리며, 길이 FIFO를 pop한다.

## 6. 변경 범위와 SBUF_TYPE

| 항목 | 처리 |
|---|---|
| `adma_dm_axi_w.sv` | WVALID 조건 및 설명 주석 변경 |
| 다른 HDL 41개 | 원본과 byte 단위 동일 |
| `common/README.md` | 원본 그대로 포함 |
| `SBUF_TYPE` | 기존 4(bypass) 유지 |
| data FIFO / 길이 FIFO / counter / WLAST 식 | 기존 구현 유지 |
| 포트, parameter, CSR map, 주소 단위 | 변경 없음 |
| 검증 TB | `feature/wvalid-fix`의 `TB/` |

이번 원인은 VALID 생성식에 READY가 들어간 것이므로 해당 식을 수정했다. Buffer type 변경으로 우회하지 않았다. Buffer type에 따라 저장 용량과 latency가 달라질 수 있으며, 그 효과는 이번 검증 범위가 아니다. 새 register나 FIFO stage는 추가하지 않았다. 면적·최대 주파수·전력의 실측 또는 합성 결과는 없다.

## 7. 수정 전후 재실행 결과

이전 결과를 옮겨 적는 데 그치지 않고, 당시 원본과 수정본을 **동일한 TB 및 실행 옵션**으로 각각 build/run했다. 소스 경로와 결과 출력 경로만 분리했다. TB의 checker나 timeout을 느슨하게 바꾸지 않았다.

| 테스트 | 확인 조건 | 수정 전 | 수정 후 |
|---|---|---|---|
| `full_ready_first` | 전체 DMA, 기존 READY-first 정책 | PASS | PASS |
| `full_fixed_stalls` | 전체 DMA, WVALID와 무관한 유한 stall | PASS | PASS |
| `full_wait_valid` | 전체 DMA, 첫 beat부터 WVALID 대기 | FAIL | **PASS** |
| `full_wait_valid_mid` | 전체 DMA, 첫 beat 수신 후 WVALID 대기 | FAIL | **PASS** |
| `unit_ready_first_1` | W module, 1-beat, READY first | PASS | PASS |
| `unit_ready_first_4` | W module, 4-beat, READY first | PASS | PASS |
| `unit_wait_valid_1` | W module, 1-beat, VALID 대기 | FAIL | **PASS** |
| `unit_wait_valid_4` | W module, 4-beat, VALID 대기 | FAIL | **PASS** |
| `unit_wait_valid_mid` | W module, 두 번째 beat부터 VALID 대기 | FAIL | **PASS** |
| 합계 | 9개 directed test | **4 PASS / 5 FAIL** | **9 PASS / 0 FAIL** |

수정 전의 5개 FAIL은 모두 `[WVALID_READY_DEPENDENCY]`로 종료했다. Runner exit code는 수정 전 1, 수정 후 0이다. `summary.json`의 `compliance_status=PASS`는 **이 runner가 선택한 9개 시험을 통과했다는 뜻**이며 전체 AXI 규격 검증 완료를 뜻하지 않는다.

### 전체 DMA의 완료 및 stall 검사

수정 후 4개 full test 모두 124 W beats(CH0 44, CH1 80), 20 AW, 20 B를 완료했다. 데이터 scoreboard, burst predictor, CSR access 및 IRQ checker를 통과했다. 각 full test의 CSR write/read는 44/24회이고 IRQ check는 11회다.

| 수정 후 full test | 데이터/길이가 준비됐지만 WREADY=0인 sampling 수 | WVALID=1, WREADY=0인 sampling 수 |
|---|---:|---:|
| `full_ready_first` | 0 | 0 |
| `full_fixed_stalls` | 237 | 237 |
| `full_wait_valid` | 495 | 495 |
| `full_wait_valid_mid` | 491 | 491 |

즉, 대기 구간에서도 WVALID를 실제로 제시했다. Hold checker는 직전 edge에서 `WVALID=1, WREADY=0`이었다면 다음 edge에서도 WVALID와 WDATA/WSTRB/WLAST가 유지되는지 확인한다. 다음 edge에서 WREADY가 1이 된 경우도 검사한다. Unit test는 1/4-beat의 WLAST 위치와 마지막 handshake 후 길이 FIFO가 비는 것까지 확인했다.

### 실제 첫 beat의 변화

아래 표는 `full_wait_valid/wvalid_trace.csv`의 clock 상승 edge 기록이다. W 누적값은 그 edge의 handshake를 포함한다.

| 시각(ns) | data valid | length valid | 수정 전 WVALID/WREADY | 수정 후 WVALID/WREADY | 수정 후 W handshake 누적 |
|---:|---:|---:|---|---|---:|
| 431 | 1 | 1 | 0 / 0 | **1 / 0** | 0 |
| 433 | 1 | 1 | 0 / 0 | **1 / 0** | 0 |
| 435 | 1 | 1 | 0 / 0 | **1 / 0** | 0 |
| 437 | 1 | 1 | 0 / 0 | **1 / 1** | **1** |

수정 전에는 493 ns에 32-cycle 진단 조건으로 FAIL했다. 수정 후에는 431 ns에 WVALID가 먼저 올라와 Slave가 이를 확인했고, 437 ns에 첫 데이터가 전송됐다. 32 cycles는 TB 진단 기준이며 AXI가 정한 최대 대기 시간이 아니다.

4-beat unit test의 마지막 beat도 225/235/245 ns에 `WVALID=1, WREADY=0, WLAST=1`로 유지됐고, 255 ns에 `WREADY=1`이 되어 네 번째 beat가 전송됐다.

## 8. 실행 환경, 경고 및 검증 한계

- Simulator: Verilator Python package `5.48.0`, `--timing --assert --trace`. 실제 version 문자열은 `rev vUNKNOWN-built20260516-4e853d8`; run banner는 Verilator 5.49다.
- Full DUT: AXI4 memory-to-memory, 256-bit data, 32-bit address, 2 channels, `ROB_EN=0`, `ATX_NUM_OSTD=2`, clock 2 ns.
- Unit DUT: 256-bit data, `ATX_NUM_OSTD=2`, clock 10 ns, 1/4-beat burst.
- 동일한 기존 build warning이 남아 있다. Full은 62건, unit은 1건으로 수정 전후 종류와 개수가 같다. Width, ascending range, TB static lifetime 등의 기존 경고를 이번 수정에서 정리하지 않았다. 당시 build 로그는 현재 저장소에 포함되어 있지 않다.
- 전체 AXI compliance, AXI Stream, 모든 data width/ROB/channel 조합, 최대 256-beat burst, reset 도중 stall, 4-state X propagation, 합성·STA는 검증하지 않았다. 본 수정의 결론은 위 조건에서 재현한 WVALID/WREADY 의존성 문제에 한정한다.

## 9. 저장소 구성 및 다시 실행하는 방법

수정본은 `feature/wvalid-fix`의 `RTL/`, 검증 TB는 `TB/`, 관련 문서는 `DOC/`에 있다. 변경 내용은 `main...feature/wvalid-fix` diff로 확인한다.

Verilator, C++ compiler, make, Python을 준비하고 저장소 최상위에서 실행한다.

```bash
python3 TB/run_wvalid_regression.py --rtl-dir RTL --out /tmp/wvalid_results --jobs 2
```

수정본의 기대 결과는 9 PASS, exit code 0이다. 수정 전 비교는 별도로 checkout한 `main`의 RTL 경로를 `--rtl-dir`에 지정하고 다른 출력 디렉터리를 사용한다. 수정 전 기대 결과는 4 PASS / 5 FAIL, exit code 1이다.

재실행 결과와 build 로그는 `--out` 디렉터리에 생성된다. 과거 실행의 원본 로그는 현재 저장소에 포함되어 있지 않다.

## 10. 규칙 확인 근거

Arm [AMBA AXI and ACE Protocol Specification, IHI 0022H](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf), A3.2.1 및 A3.3.1을 확인했다. Master의 VALID는 상대의 READY를 기다려 assert하면 안 되며, assert한 VALID와 payload는 handshake까지 유지해야 한다. Slave는 VALID를 확인한 뒤 READY를 assert할 수 있다. 이 규칙에 맞춰 VALID 생성과 데이터 소비 조건을 분리했다.

