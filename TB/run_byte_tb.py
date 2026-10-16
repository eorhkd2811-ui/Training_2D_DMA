#!/usr/bin/env python3
"""Build the copied TB against Byte-address RTL, then run a selected scenario.

Example:
  python3 run_byte_tb.py --rtl-dir /project/rtl --rtl-overlay /project/modified_rtl \
      --common-dir /project/rtl/common --scenario CUSTOM
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl-dir',type=Path,required=True)
    p.add_argument('--rtl-overlay',type=Path,action='append',default=[],
                   help='repeat for overlays; later folders override earlier basenames')
    p.add_argument('--common-dir',type=Path)
    p.add_argument('--verilator')
    p.add_argument('--scenario',choices=['CUSTOM','IMG_STREAM','WREADY_WAIT_VALID','WREADY_WAIT_VALID_MID'],default='IMG_STREAM')
    p.add_argument('--stall-max',type=int,default=0)
    p.add_argument('--timeout-ns',type=int,default=200000)
    p.add_argument('--build-dir',type=Path)
    p.add_argument('--run-dir',type=Path)
    p.add_argument('--image-input',type=Path)
    p.add_argument('--generate-image-pattern',action='store_true')
    p.add_argument('--inject-data',action='store_true')
    p.add_argument('--inject-address',action='store_true')
    p.add_argument('--inject-predictor',action='store_true',help='checker self-test: corrupt first local ARLEN observation')
    p.add_argument('--inject-irq-clear',action='store_true',help='checker self-test: corrupt local RW1C readback observation')
    p.add_argument('--monitor',action='store_true')
    p.add_argument('--build-only',action='store_true')
    p.add_argument('--no-build',action='store_true')
    a=p.parse_args()
    if not 0<=a.stall_max<=1000 or a.timeout_ns<=0:
        p.error('STALL_MAX must be 0..1000 and timeout must be positive')
    if a.image_input and a.generate_image_pattern:
        p.error('choose either image input or generated image pattern')
    here=Path(__file__).resolve().parent
    rtl=a.rtl_dir.resolve()
    common=(a.common_dir or rtl/'common').resolve()
    build=(a.build_dir or here/'build_byte').resolve()
    run=(a.run_dir or here/'run_byte'/a.scenario).resolve()
    build.mkdir(parents=True,exist_ok=True)
    (run/'env').mkdir(parents=True,exist_ok=True)
    # Do not compile duplicate historical top modules such as axi_dma_old.sv.
    files={f.name:f for f in sorted(rtl.glob('adma_*.sv'))}
    files['axi_dma.sv']=rtl/'axi_dma.sv'
    for overlay in a.rtl_overlay:
        files.update({f.name:f.resolve() for f in overlay.glob('*.sv')
                      if f.name=='axi_dma.sv' or f.name.startswith('adma_')})
    shared=[]
    for folder in ['adapter/axi','arbiter/iwrr','edgedet','encoder/onehot_encoder',
                   'fifo/sync_fifo','skid_buffer','reorder_buffer','splitter']:
        shared.extend(sorted((common/folder).glob('*.v')))
    tb=[here/name for name in ['tb_var.sv','tb_dpi.sv','tb_if.sv','tb_drv.sv','tb_seq.sv',
        'tb_monitor.sv','tb_sb.sv','tb_duv.sv','tb_wvalid_check.sv','tb_top.sv','axi_dma_tb.sv','tb_ref.cpp']]
    sources=tb+list(files.values())+shared
    for file in sources:
        if not file.is_file(): p.error(f'missing source: {file}')
    if not (common/'splitter/splitter.v').is_file(): p.error('common source tree not found')
    simulator=[a.verilator] if a.verilator else ([shutil.which('verilator')] if shutil.which('verilator')
                                                else [sys.executable,'-m','verilator'])
    command=simulator+['--binary','--timing','--assert','-Wno-fatal','--top-module','axi_dma_tb',
        '-j','4','-MAKEFLAGS','CFG_CXXFLAGS_PCH_I=-include','--Mdir',str(build)]+[str(f) for f in sources]
    manifest=dict(scenario=a.scenario,stall_max=a.stall_max,build_command=command,
        source_sha256={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources})
    if a.no_build:
        previous=build/'build_result.json'
        prior=json.loads(previous.read_text()) if previous.is_file() else {}
        if (prior.get('build_returncode')!=0 or prior.get('source_sha256')!=manifest['source_sha256']
                or not (build/'Vaxi_dma_tb').is_file()):
            p.error('--no-build requires unchanged sources from a successful prior build')
    if not a.no_build:
        with (build/'build.log').open('w') as log:
            rc=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT).returncode
        manifest['build_returncode']=rc
        if rc:
            (build/'build_result.json').write_text(json.dumps(manifest,indent=2))
            print(f'BUILD FAIL: {build/"build.log"}',file=sys.stderr)
            return 1
        (build/'build_result.json').write_text(json.dumps(manifest,indent=2))
    if a.build_only:
        print(f'BUILD PASS: {build/"Vaxi_dma_tb"}')
        return 0
    (run/'env/tb_result.txt').unlink(missing_ok=True)
    if a.scenario=='IMG_STREAM':
        dest=run/'env/src_mem.txt'
        if a.image_input:
            if a.image_input.resolve()!=dest: shutil.copyfile(a.image_input,dest)
            manifest['image_input']=str(a.image_input.resolve())
        elif a.generate_image_pattern:
            # Explicit synthetic RGB565 pattern: not the user's original image.
            with dest.open('w') as f:
                for word in range(640*480//16):
                    value=0
                    for lane in range(16):
                        pixel=word*16+lane; x=pixel%640; y=pixel//640
                        rgb=((x&31)<<11)|((y&63)<<5)|((x^y)&31)
                        value|=rgb<<(16*lane)
                    f.write(f'{value:064x}\n')
            manifest['image_input']='generated synthetic 640x480 RGB565 pattern'
        else:
            p.error('IMG_STREAM requires --image-input or --generate-image-pattern')
        manifest['image_sha256']=hashlib.sha256(dest.read_bytes()).hexdigest()
    args=[str(build/'Vaxi_dma_tb'),f'+SCENARIO={a.scenario}',f'+STALL_MAX={a.stall_max}',
          f'+TIMEOUT_NS={a.timeout_ns}']
    if a.inject_data: args.append('+SB_INJECT_ERROR=1')
    if a.inject_address: args.append('+SB_INJECT_ADDR_ERROR=1')
    if a.inject_predictor: args.append('+PRED_INJECT_LEN_ERROR=1')
    if a.inject_irq_clear: args.append('+IRQ_INJECT_CLEAR_ERROR=1')
    if a.monitor: args.append('+MONITOR')
    manifest['run_command']=args
    # Avoid large crash core files when an expected checker test calls $fatal.
    if os.name=='posix':
        import resource
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    with (run/'run.log').open('w') as log:
        try:
            rc=subprocess.run(args,cwd=run,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
        except subprocess.TimeoutExpired:
            rc=124; log.write('\n[RUNNER] wall-clock timeout after 60 seconds\n')
    manifest['run_returncode']=rc
    # Require an explicit scoreboard PASS in addition to a zero simulator exit.
    contents=(run/'run.log').read_text()
    passed=(rc==0 and '[TB_PASS]' in contents and '[IRQ_PASS]' in contents
            and '[PRED SUMMARY]' in contents and (run/'env/tb_result.txt').is_file())
    manifest['pass']=passed
    (run/'result.json').write_text(json.dumps(manifest,indent=2))
    print('\n'.join(contents.splitlines()[-12:]))
    print(f'RESULT {"PASS" if passed else "FAIL"}: {run/"run.log"}')
    return 0 if passed else 1


if __name__=='__main__':
    sys.exit(main())
