#!/usr/bin/env python3
"""Run directed WVALID/WREADY tests against an external, unmodified Latest RTL tree.
Exit 0: every selected test passed. Exit 1: DUT/test failure. Exit 2: setup/build error.
Known-bug failures are NEVER converted to PASS.
"""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
CASES = [
    ('full_ready_first', 'full', ['+SCENARIO=CUSTOM', '+STALL_MAX=0']),
    ('full_fixed_stalls', 'full', ['+SCENARIO=CUSTOM', '+STALL_MAX=4']),
    ('full_wait_valid', 'full', ['+SCENARIO=WREADY_WAIT_VALID', '+STALL_MAX=0']),
    ('full_wait_valid_mid', 'full', ['+SCENARIO=WREADY_WAIT_VALID_MID', '+STALL_MAX=0']),
    ('unit_ready_first_1', 'unit', ['+MODE=READY_FIRST', '+BEATS=1']),
    ('unit_ready_first_4', 'unit', ['+MODE=READY_FIRST', '+BEATS=4']),
    ('unit_wait_valid_1', 'unit', ['+MODE=WAIT_VALID', '+BEATS=1']),
    ('unit_wait_valid_4', 'unit', ['+MODE=WAIT_VALID', '+BEATS=4']),
    ('unit_wait_valid_mid', 'unit', ['+MODE=WAIT_VALID_MID', '+BEATS=4']),
]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rtl-dir', type=Path, required=True, help='Downloaded Latest RTL folder; common/ is beneath it')
    parser.add_argument('--common-dir', type=Path)
    parser.add_argument('--verilator', help='Verilator executable; otherwise PATH or python -m verilator')
    parser.add_argument('--out', type=Path, default=HERE/'results')
    parser.add_argument('--case', choices=['all']+[x[0] for x in CASES], default='all')
    parser.add_argument('--timeout-cycles', type=int, default=32, help='Diagnostic bound, not an AXI timing requirement')
    parser.add_argument('--no-build', action='store_true', help='Require a successful build with identical sources/options')
    parser.add_argument('--jobs', type=int, default=1)
    parser.add_argument('--no-wave', action='store_true')
    args=parser.parse_args()
    if not 2<=args.timeout_cycles<=10000 or args.jobs<1: parser.error('invalid bound/jobs')
    rtl=args.rtl_dir.resolve(); common=(args.common_dir or rtl/'common').resolve()
    out=args.out.resolve(); out.mkdir(parents=True,exist_ok=True)
    if out.is_relative_to(rtl) or out.is_relative_to(common):
        parser.error('--out must be outside RTL/common; sources are read-only')
    simulator=[args.verilator] if args.verilator else ([shutil.which('verilator')] if shutil.which('verilator') else [sys.executable,'-m','verilator'])
    try:
        version=subprocess.check_output(simulator+['--version'],stderr=subprocess.STDOUT,text=True).strip()
    except (OSError,subprocess.CalledProcessError) as exc:
        print(f'SETUP ERROR: Verilator not available: {exc}',file=sys.stderr); return 2
    try: wheel_version=importlib.metadata.version('verilator')
    except importlib.metadata.PackageNotFoundError: wheel_version=None
    selected=[x for x in CASES if args.case in ('all',x[0])]
    shared=[]
    for folder in ['adapter/axi','arbiter/iwrr','edgedet','encoder/onehot_encoder',
                   'fifo/sync_fifo','skid_buffer','reorder_buffer','splitter']:
        shared.extend(sorted((common/folder).glob('*.v')))
    tb=[HERE/name for name in ['tb_var.sv','tb_dpi.sv','tb_if.sv','tb_drv.sv','tb_seq.sv',
        'tb_monitor.sv','tb_sb.sv','tb_duv.sv','tb_wvalid_check.sv','tb_top.sv','axi_dma_tb.sv','tb_ref.cpp']]
    sources={
        'full':tb+sorted(rtl.glob('adma_*.sv'))+[rtl/'axi_dma.sv']+shared,
        'unit':[HERE/'tb_wvalid_unit.sv',rtl/'adma_dm_axi_w.sv',
                common/'fifo/sync_fifo/sync_fifo.v',common/'fifo/sync_fifo/fifo.v',
                common/'skid_buffer/skid_buffer.v',common/'skid_buffer/sb_fifo.v'],
    }
    # Protect every RTL/common source, including files unused by the selected top.
    rtl_files=sorted(set(rtl.rglob('*.sv')) | set(rtl.rglob('*.v')) |
                     set(common.rglob('*.sv')) | set(common.rglob('*.v')))
    if not rtl_files: parser.error('RTL source tree is empty')
    before={str(p):digest(p) for p in rtl_files}
    summary={'simulator':version,'verilator_python_package':wheel_version,
             'timeout_cycles':args.timeout_cycles,'cases':[],
             'rtl_hash_before':before,'note':'FAIL remains FAIL even when it reproduces the known bug.'}
    if os.name=='posix':
        import resource
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    binaries={}
    for scope in dict.fromkeys(x[1] for x in selected):
        for p in sources[scope]:
            if not p.is_file(): parser.error(f'missing source: {p}')
        top='axi_dma_tb' if scope=='full' else 'tb_wvalid_unit'
        build=out/('build_'+scope); build.mkdir(exist_ok=True)
        command=simulator+['--binary','--timing','--assert','--trace','--trace-depth','8',
            '-Wno-fatal','--top-module',top,'-j',str(args.jobs),
            '-MAKEFLAGS','CFG_CXXFLAGS_PCH_I=-include','--Mdir',str(build)]+[str(f) for f in sources[scope]]
        hashes={str(p):digest(p) for p in sources[scope]}
        signature={'source_sha256':hashes,'command':command,'simulator':version}
        manifest_path=build/'build_result.json'; binary=build/('V'+top)
        prior=json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        reusable=prior.get('returncode')==0 and prior.get('signature')==signature and binary.is_file()
        if args.no_build and not reusable: parser.error('--no-build requires unchanged sources/options from successful build')
        if not reusable:
            with (build/'build.log').open('w') as log:
                rc=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT).returncode
            manifest_path.write_text(json.dumps({'returncode':rc,'signature':signature},indent=2)+'\n')
            if rc:
                print(f'BUILD ERROR: {build/"build.log"}',file=sys.stderr); return 2
        binaries[scope]=binary
    for name,scope,plusargs in selected:
        run=out/name; (run/'env').mkdir(parents=True,exist_ok=True)
        for stale in ['run.log','wave.vcd','wvalid_trace.csv','unit_trace.csv','env/tb_result.txt']:
            (run/stale).unlink(missing_ok=True)
        command=[str(binaries[scope])]+plusargs+[f'+WVALID_TIMEOUT_CYCLES={args.timeout_cycles}','+MONITOR']
        if scope=='full': command+=['+TIMEOUT_NS=200000']
        if not args.no_wave: command+=['+DUMP_WAVE']
        with (run/'run.log').open('w') as log:
            try: rc=subprocess.run(command,cwd=run,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
            except subprocess.TimeoutExpired: rc=124; log.write('\n[RUNNER_TIMEOUT] 60 seconds\n')
        contents=(run/'run.log').read_text(errors='replace')
        tokens=['[TB_PASS]','[IRQ_PASS]','[PRED SUMMARY]'] if scope=='full' else ['[UNIT_PASS]']
        passed=rc==0 and all(t in contents for t in tokens)
        if scope=='full': passed=passed and (run/'env/tb_result.txt').is_file()
        evidence=[line for line in contents.splitlines() if any(t in line for t in
            ['[WVALID_EVIDENCE]','[UNIT_EVIDENCE]','[TB_PASS]','[UNIT_PASS]','[WCHK_SUMMARY]'])]
        dependency_fail='[WVALID_READY_DEPENDENCY]' in contents
        result={'case':name,'scope':scope,'status':'PASS' if passed else 'FAIL',
                'returncode':rc,'dependency_failure':dependency_fail,
                'command':command,'evidence':evidence}
        (run/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        summary['cases'].append(result)
        print(f'{name}: {result["status"]} (rc={rc}, dependency_failure={dependency_fail})')
        for line in evidence: print('  '+line)
    after={str(p):digest(p) for p in rtl_files}
    summary['rtl_hash_after']=after; summary['rtl_unchanged']=(before==after)
    summary['compliance_status']='PASS' if all(r['status']=='PASS' for r in summary['cases']) and before==after else 'FAIL'
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'RTL_UNCHANGED={before==after}; COMPLIANCE={summary["compliance_status"]}')
    return 0 if summary['compliance_status']=='PASS' else 1

if __name__=='__main__': sys.exit(main())
