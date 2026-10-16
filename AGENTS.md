# AGENTS.md — Training_2D_DMA

이 파일은 Codex처럼 `AGENTS.md`를 읽는 에이전트용 안내다. 이 저장소의 규칙 원본은 최상위 `CLAUDE.md` 하나다.

## 작업 전에 반드시
1. 저장소 최상위의 `CLAUDE.md`를 처음부터 끝까지 읽고 그대로 따른다. 프로젝트 목표, 핵심 결정(브랜치 규칙, AXIS 범위 외), RTL 코딩 규칙, TB/검증 규칙, 문서 규칙이 모두 그 파일에 있다.
2. 이 파일과 `CLAUDE.md`의 내용이 다르면 `CLAUDE.md`를 따른다.
3. 규칙을 바꿀 때는 `CLAUDE.md`만 고친다. 이 파일에 규칙을 복사하지 않는다.

## Codex에서 다른 점
- `.claude/settings.json`의 SessionStart hook은 Claude Code에서만 실행된다. Codex에서는 시뮬레이션 전에 Verilator를 직접 설치한다.
  ```bash
  bash TB/env/setup_verilator.sh
  ```
  스크립트가 출력하는 `Add to PATH: export PATH=...` 줄에서 `export` 명령을 실행한 뒤, `verilator --version`으로 버전을 확인한다.
