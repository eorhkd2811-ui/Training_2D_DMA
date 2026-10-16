# BUG-AXI-W-001: WVALID가 WREADY에 의존하여 합법적인 Slave와 deadlock 발생

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-14, Asia/Seoul |
| 상태 | **재현 완료 / RTL 미수정** |
| 중요도 | High — 합법적인 Slave의 WREADY 정책에서 DMA write 진행 불가 |
| DUT | Latest RTL의 `axi_dma`, 원인 모듈 `adma_dm_axi_w` |
| 인터페이스 | AXI4 memory-to-memory, 256-bit data, 32-bit address |
| 결과 | 9개 directed test: 대조군 4 PASS, WVALID 대기 조건 5 FAIL |
| 원본 보존 | RTL/common 42개 파일 실행 전후 SHA-256 동일; 원본 Latest TB도 미수정 |

## 1. 결론과 영향

Master의 `m_wvalid_o`에 Slave 입력 `m_wready_i`가 조합논리로 포함되어 있다. 따라서 Slave가 **WVALID를 확인한 뒤 WREADY를 올리는 합법적인 방식**으로 동작하면, write data와 burst 길이 정보가 준비되어도 양측이 서로 기다린다.

전체 DMA에서 첫 write beat가 전송되지 않는 경우와, 첫 beat를 전송한 뒤 두 번째 beat에서 멈추는 경우를 모두 재현했다. W-channel 단독 검증에서도 1-beat 및 4-beat burst로 재현했다. 새로운 TB는 실패 시 `$fatal`과 비정상 종료를 발생시키며, 알려진 버그 재현을 PASS로 바꾸지 않는다.

## 2. 기준 소스와 환경

- [Latest RTL](https://drive.google.com/drive/folders/1ehUlPQDRaGnAK8QyKzYIfxUSIOIRaxt6): 2026-10-14에 직접 내려받은 원본.
- [Latest TB](https://drive.google.com/drive/folders/111CWPsMUAUIsp1iRsZKROQhU6BQut0nA): 별도 사본으로 확장. 기존 CUSTOM descriptor, reference model, predictor, CSR/IRQ checker를 유지했다.
- 원인 파일: [adma_dm_axi_w.sv](https://drive.google.com/file/d/1ZGi542NrF4wk38z3TXOGgw2iGe_Yk9og/view?usp=drivesdk).
- `adma_dm_axi_w.sv`의 Drive 수정 시각: `2026-10-13T05:21:49.162Z`.
- 파일 SHA-256: `717c65792a2f750ad6f00614016609fc8140484194318f56f79bc90b987f72cd`.
- `common/skid_buffer/skid_buffer.v` SHA-256: `756d3ed33277a2b6f2ec39b47cc78f23dd3cffcc28a942ebb06072c3773b489d`.
- 전체 source ID, 경로, 수정 시각, 크기, SHA-256: [SOURCE_MANIFEST.json](SOURCE_MANIFEST.json).
- 실행 환경: Linux, Python 3.12, Verilator Python package `5.48.0`, `--timing --assert --trace`. 해당 배포물의 version 출력은 `rev vUNKNOWN-built20260516-4e853d8`, 실행 banner는 `Verilator 5.49`였다. 정확한 command는 `evidence/build_*/build_result.json`에 보존했다.
- Full DUT: 2 channels, 256-bit, ROB_EN=0, ATX_NUM_OSTD=2, clock period=2 ns. Unit DUT: 256-bit, ATX_NUM_OSTD=2, clock period=10 ns.
- RTL parameter 또는 SBUF_TYPE 변경, RTL overlay, `force/release`, DUT 내부 신호 할당을 사용하지 않았다. 내부 상태는 read-only probe로만 관찰했다.

## 3. AXI 규칙

Arm **AMBA AXI and ACE Protocol Specification, IHI 0022E, A3.3.1, A3-42~A3-44**의 handshake dependency 규칙에 따르면, Master는 WREADY를 기다려 WVALID를 올리면 안 된다. Slave는 WVALID를 기다린 뒤 WREADY를 올릴 수 있다. WVALID가 제시된 후 backpressure가 걸리면 handshake까지 VALID와 payload를 유지해야 한다.

공식 문서: [Arm IHI 0022E](https://documentation-service.arm.com/static/5f915b62f86e16515cdc3b1c).

**이 검증의 32-cycle timeout은 AXI가 정한 최대 지연 시간이 아니다.** 데이터와 burst 정보가 준비된 상태에서 진행이 없는 것을 검출하는 directed test의 관찰 한계다. 버그 판정은 timeout 결과와 아래 RTL 조합논리 의존성을 함께 근거로 한다.

## 4. 원인 분석

`adma_dm_axi_w.sv` 75~77행:

```systemverilog
assign db_hsk   = atx_wdata_vld & atx_wdata_rdy;
assign m_wvalid = atx_wdata_vld & atx_wdata_rdy;
assign atx_wdata_rdy = m_wready & wdata_len_vld;
```

같은 파일 40행의 `SBUF_TYPE=4`는 bypass다. `common/skid_buffer/skid_buffer.v` 338~341행에서 VALID는 그대로 출력되고 READY는 그대로 역전달된다.

```systemverilog
assign fwd_valid_o = bwd_valid_i;
assign bwd_ready_o = fwd_ready_i;
```

현재 구성에서는 아래 식이 성립한다.

```text
m_wvalid_o = atx_wdata_vld & wdata_len_vld & m_wready_i
```

즉, **데이터가 유효하다는 표시인 WVALID를 전송이 성립하는 조건인 handshake와 동일하게 생성**한다. WREADY=0이면 데이터가 준비되어도 WVALID=0이다. 반대편 Slave도 WVALID를 기다리면 이 상태에서 빠져나갈 수 없다.

## 5. 새 시나리오와 checker

| 시나리오 | Slave WREADY 동작 | 목적 |
|---|---|---|
| `CUSTOM`, STALL_MAX=0 | 기존처럼 WREADY를 먼저 올림 | 동일 descriptor/데이터 경로의 정상 전송 대조군 |
| `CUSTOM`, STALL_MAX=4 | WVALID와 무관한 유한 stall 후 WREADY를 올림 | 단순 stall만으로는 버그를 놓칠 수 있음을 확인 |
| `WREADY_WAIT_VALID` | 첫 beat부터 매 beat마다 WREADY=0으로 대기, WVALID를 sampling한 후에만 올림 | 최초 VALID의 READY 독립성 검출 |
| `WREADY_WAIT_VALID_MID` | 첫 beat는 기존 방식으로 수신, 이후 매 beat마다 WVALID를 기다림 | burst 중간 beat에도 동일 규칙이 적용되는지 검출 |

새 시나리오는 CUSTOM의 CH0→CH1→CH0 descriptor 3개를 재사용한다. 정상 완료 기준 총 124 beats(CH0 44, CH1 80)이며, CH0 burst 상한은 6 beats, CH1은 8 beats다. 이름과 Slave 정책만 바꾸어 데이터 경로를 비교한다.

`tb_drv.sv`는 WREADY를 falling edge에서만 변경하고 WVALID는 rising edge에서 관찰한다. WVALID를 확인하면 추가 2 cycles 동안 WREADY를 낮게 유지한 뒤 수신한다. 조합논리 `WREADY=WVALID` 연결이나 timeout 시 강제 WREADY 해제는 사용하지 않는다.

`tb_wvalid_check.sv`는 다음을 수행한다.

1. `atx_wdata_vld=1`, `wdata_len_vld=1`, `WREADY=0`, `WVALID=0`이 연속 32회 sampling되는지 검사한다. 조건이 깨지면 count를 초기화한다.
2. AW/R/W/B handshake 수와 내부 data/length 준비 상태를 CSV 및 오류 메시지로 남긴다.
3. `WVALID=1 && WREADY=0`이 관찰된 경우 다음 sampling edge까지 VALID/WDATA/WSTRB/WLAST가 유지되는지 검사한다. 다음 edge에서 READY가 1이 되어도 동일 검사를 적용한다.
4. 데이터나 descriptor가 준비되지 않아 멈춘 경우에는 별도의 global timeout으로 구분한다. 단순히 AW 이후 시간이 지났다는 이유만으로 이번 버그를 판정하지 않는다.

## 6. 실제 실행 결과

| 테스트 | 조건 | 결과 | 재현 근거 |
|---|---|---|---|
| `full_ready_first` | 전체 DMA, 기존 WREADY 정책 | PASS | 124 W beats, 20 AW, 20 B, data/predictor/IRQ 검사 통과 |
| `full_fixed_stalls` | 전체 DMA, STALL_MAX=4 | PASS | 124 W beats, 20 AW, 20 B; WREADY=0/data ready 구간 237 cycles |
| `full_wait_valid` | 전체 DMA, 첫 beat부터 WVALID 대기 | **FAIL** | 493 ns: AW=2, R=2, W=0, B=0 |
| `full_wait_valid_mid` | 전체 DMA, 첫 beat 후 WVALID 대기 | **FAIL** | 497 ns: AW=2, R=3, W=1, B=0 |
| `unit_ready_first_1` | W module, 1 beat, READY first | PASS | 1/1 beat 및 WLAST 검사 통과 |
| `unit_ready_first_4` | W module, 4 beats, READY first | PASS | 4/4 beats 및 WLAST 검사 통과 |
| `unit_wait_valid_1` | W module, 1 beat, VALID 대기 | **FAIL** | 385 ns, 0/1 beat |
| `unit_wait_valid_4` | W module, 4 beats, VALID 대기 | **FAIL** | 385 ns, 0/4 beats |
| `unit_wait_valid_mid` | W module, 4 beats, 첫 beat 후 VALID 대기 | **FAIL** | 405 ns, 1/4 beats |

위의 R/W는 beat handshake 수이며 AW/B는 transaction handshake 수다. 5개 FAIL 모두 `[WVALID_READY_DEPENDENCY]`로 종료했다. Runner 전체 exit code는 1이며, 결과 파일의 `compliance_status`도 `FAIL`이다.

### 첫 beat에서의 증거

| 시각(ns) | 연속 관찰 수 | data valid | length valid | data ready | WVALID | WREADY | W handshake 누적 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 431 | 1 | 1 | 1 | 0 | 0 | 0 | 0 |
| 433 | 2 | 1 | 1 | 0 | 0 | 0 | 0 |
| 493 | 32 | 1 | 1 | 0 | 0 | 0 | 0 |

2 ns 간격의 32개 sampling edge에서 준비 상태가 유지됐다. 첫 관찰부터 마지막 관찰까지의 시각 차이는 62 ns다. 마지막 edge에서 checker가 실패를 보고했다.

실제 로그:

```text
[WVALID_EVIDENCE] scenario=WREADY_WAIT_VALID t_ns=493.000 cycles=32 AW=2 R=2 W=0 B=0 data_vld=1 len_vld=1 data_rdy=0 WVALID=0 WREADY=0
[WVALID_READY_DEPENDENCY] ready data and burst information remained pending while Slave waited for WVALID
```

중간 beat 테스트에서도 435~497 ns의 32개 sampling edge 동안 동일 상태가 유지됐고, W handshake 누적은 1에서 증가하지 않았다.

## 7. 재현 방법

TB 폴더에서 다음 명령을 실행한다. `Latest RTL`과 그 하위 `common` 디렉토리가 필요하며, TB 패키지에는 RTL 복사본을 넣지 않았다.

```bash
python3 run_wvalid_regression.py \
  --rtl-dir "/path/to/Latest RTL" \
  --out ./results --jobs 1
```

첫 beat 실패만 재현:

```bash
python3 run_wvalid_regression.py \
  --rtl-dir "/path/to/Latest RTL" \
  --out ./results --jobs 1 --case full_wait_valid
```

W-channel 단독 1-beat 재현:

```bash
python3 run_wvalid_regression.py \
  --rtl-dir "/path/to/Latest RTL" \
  --out ./results --jobs 1 --case unit_wait_valid_1
```

Simulator가 PATH에 없으면 Python의 `verilator` package를 사용한다. 검증에 사용한 package는 `5.48.0`이다. C++ compiler와 make가 필요하다. 전체 DMA TB는 mailbox/interface/DPI-C/timing을 사용하므로 SystemVerilog 지원이 필요하다. `--no-build`는 성공한 build와 source hash/command가 모두 같을 때만 허용된다.

증거는 `evidence/summary.json`, 각 case의 `run.log`, `result.json`, `*_trace.csv`, `wave.vcd`에 있다. Full waveform에서 확인할 경로는 다음과 같다.

```text
axi_dma_tb.env.bus.m_wvalid_o
axi_dma_tb.env.bus.m_wready_i
axi_dma_tb.env.bus.m_wdata_o
axi_dma_tb.env.bus.m_wlast_o
axi_dma_tb.env.duv.dut.dm.wh.DST_AXI4_GEN.w.atx_wdata_vld
axi_dma_tb.env.duv.dut.dm.wh.DST_AXI4_GEN.w.wdata_len_vld
axi_dma_tb.env.duv.dut.dm.wh.DST_AXI4_GEN.w.atx_wdata_rdy
```

## 8. 수정 방향 및 검증 범위

수정 방향은 WVALID를 데이터/metadata의 유효성으로 생성하고, 실제 데이터 소비와 counter 갱신은 handshake에 유지하는 것이다. 예를 들어 현재 bypass 구조에서 `atx_wdata_vld & wdata_len_vld`를 VALID 조건으로 검토할 수 있다. **이는 검토 제안이며, RTL 수정이나 수정안 시뮬레이션은 수행하지 않았다.** Buffer type 변경의 효과도 이번 검증 범위에 포함하지 않았다.

현재 버그 때문에 VALID가 READY보다 먼저 제시되는 경우는 실행된 테스트에서 관찰되지 않았다. 따라서 VALID/payload hold checker는 포함했지만 그 정상 경로를 통과했다고 주장하지 않는다. 수정 후에는 새 시나리오의 정상 완료, stalled payload 안정성, 최종 beat/WLAST, 다음 burst와 data/predictor/IRQ regression을 다시 확인해야 한다.

이번 결과는 명시한 구성과 directed 시나리오의 검증 결과다. 전체 AXI compliance, AXI Stream, 모든 ROB/채널/데이터폭 조합, X propagation, reset 도중 stall은 검증하지 않았다. Verilator의 2-state 실행 결과이므로 4-state X 검증 완료를 의미하지 않는다.
