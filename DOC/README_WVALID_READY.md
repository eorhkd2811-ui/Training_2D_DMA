# AXI WVALID / WREADY dependency 검증 TB

`Latest RTL`을 수정하지 않고, Slave가 WVALID를 기다린 뒤 WREADY를 올리는 동작으로 Master의 금지된 READY 의존성을 재현하는 TB다.

**실행 결과: 9 tests 중 4 PASS / 5 FAIL. 버그 재현 완료이며 RTL은 미수정이다.**

## 빠른 실행

1. 이 폴더와 별도로 [Latest RTL](https://drive.google.com/drive/folders/1ehUlPQDRaGnAK8QyKzYIfxUSIOIRaxt6)을 하위 `common` 폴더까지 다운로드한다.
2. Python 3.9 이상, Verilator 및 C++ compiler/make가 필요하다. 이번 실행은 Python 3.12와 Verilator Python package 5.48.0을 사용했다.
3. 이 폴더에서 실행한다.

```bash
python3 run_wvalid_regression.py --rtl-dir "/path/to/Latest RTL" --out ./results --jobs 1
```

`common`이 다른 위치라면 `--common-dir "/path/to/common"`을 추가한다. Verilator 실행 파일 경로를 지정하려면 `--verilator /path/to/verilator`를 사용한다. PATH에 실행 파일이 없으면 `python -m verilator`로 실행한다.

실행 결과는 `results/summary.json`, 각 case의 `run.log`/CSV/VCD에 생성된다. 재현된 버그는 FAIL이며 runner의 exit code는 **1**이다. 모든 선택 case가 통과하면 0, setup/build 오류이면 2이다. `--out`은 RTL/common 디렉토리 밖이어야 한다.

```bash
# 대조군
python3 run_wvalid_regression.py --rtl-dir "/path/to/Latest RTL" --case full_ready_first

# 첫 write beat에서 WVALID 대기
python3 run_wvalid_regression.py --rtl-dir "/path/to/Latest RTL" --case full_wait_valid

# 첫 beat 수신 후 다음 beat에서 WVALID 대기
python3 run_wvalid_regression.py --rtl-dir "/path/to/Latest RTL" --case full_wait_valid_mid

# W module 단독 1-beat 재현
python3 run_wvalid_regression.py --rtl-dir "/path/to/Latest RTL" --case unit_wait_valid_1
```

`--timeout-cycles 32`는 test의 진단 기준이며 AXI의 최대 지연 규정이 아니다. `--no-wave`는 VCD 출력을 생략한다. 성공한 build와 source/options가 동일하면 자동 재사용하며, `--no-build`는 그 일치 여부를 강제 확인한다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `run_wvalid_regression.py` | 9개 테스트 build/run, PASS/FAIL, SHA-256 불변 확인 |
| `tb_drv.sv` | 기존 Memory BFM에 WVALID 대기 정책 추가 |
| `tb_seq.sv` | 새 시나리오 이름을 허용하고 기존 CUSTOM descriptor 재사용 |
| `tb_top.sv` | 신규 checker 연결 및 VCD 제어; 내부 read-only probe |
| `tb_wvalid_check.sv` | 준비 상태 기반 progress bound, stalled VALID/payload 검사, CSV |
| `tb_wvalid_unit.sv` | 미수정 `adma_dm_axi_w` 단독 1/4-beat 재현 |
| 나머지 SV / `tb_ref.cpp` | Latest TB에서 가져온 DUT wrapper, interface, reference/predictor/CSR/IRQ 검사 |
| `run_byte_tb.py` | 기존 runner 사본. 새 checker와 scenario 선택을 반영했으며, 본 결과는 `run_wvalid_regression.py`로 실행 |
| `BUG_AXI_WVALID_DEPENDS_ON_WREADY.md` | 원인 코드, 규칙, 재현 절차, 실제 로그, 영향 및 범위 |
| `SOURCE_MANIFEST.json` | 내려받은 원본 RTL/common/TB의 Drive ID와 SHA-256 |
| `TB_CHANGES.patch` | Latest TB 대비 이 사본의 추가/변경 내용 |
| `evidence/` | 실제 실행 로그/CSV/VCD, build 기록, JSON 결과 |

원본 RTL/Latest TB를 덮어쓰지 않는다. 패키지에 RTL, compiler, simulator executable, build object는 포함하지 않았다. 실행 경로가 기록된 JSON은 이번 실행의 증거이며 다른 컴퓨터에서는 위 명령으로 새 build를 생성한다.

Full DUT 조건: 2 channels, AXI4→AXI4, 256-bit, ROB_EN=0, ATX_NUM_OSTD=2. IMG_STREAM과 원본 image 변환 도구는 이번 regression 범위가 아니므로 별도 image 자산을 이 패키지에 포함하지 않았다.
