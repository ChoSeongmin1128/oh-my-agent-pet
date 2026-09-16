# Oh My Agent Pet

Oh My Agent Pet은 Claude Code와 Codex 작업 상태를 한 마리의 macOS 데스크톱 펫으로 보여주는 독립 오픈소스 앱입니다.

현재 첫 릴리스를 구현하고 있으며 아직 설치 가능한 버전은 없습니다.

## 현재 구현 상태

- macOS 14 이상 Swift/AppKit 메뉴바 앱과 앱 번들에 포함되는 `omapet` CLI
- Claude Code와 Codex 연결 상태 확인, dry-run, 연결과 연결 해제
- Codex app-server의 현재 hook 해시를 이용한 명시적 신뢰 등록과 자기 신뢰 항목 제거
- 프롬프트 본문과 도구 입출력을 제외한 두 공급자의 최소 hook 이벤트 로컬 기록
- 앱 시작 시 기존 이벤트 재생과 이후 Claude·Codex 변경의 실시간 감지
- Codex session index·rollout 읽기와 `PermissionRequest` 승인 대기 결합
- 입력 필요, 작업 중, 완료와 실패를 대표 작업 메뉴 상태로 표시
- Apple Silicon과 Intel을 함께 검증하는 GitHub Actions CI

현재 소스 코드는 앱 기반과 Claude·Codex 상태 관찰 및 CLI 연결 경로까지 구현한 개발 버전입니다. 펫과 카드 화면, 정확한 작업 이동, 설정 화면과 서명된 업데이트는 아직 구현 중입니다.

## 목표 기능

- Claude Code와 Codex 작업 상태 통합
- 한 마리의 펫으로 작업 중, 입력 필요, 실패와 완료 표현
- 작업 카드를 눌러 정확한 앱, 창과 터미널 세션으로 이동
- 카드 내용, 펫 움직임, 시선과 표시 방식 사용자 설정
- Claude만 사용하는 구성 지원
- 사용자 펫과 Codex 호환 펫 포맷 지원
- 로컬 진단 창과 명시적인 진단 자료 내보내기
- 서명된 앱 내 업데이트 확인과 설치

최소 지원 환경은 macOS 14로 설정되어 있습니다.

## 설치

첫 안정 릴리스 이후 Homebrew Cask를 기본 설치 경로로 제공합니다.

```bash
brew install --cask choseongmin1128/tap/oh-my-agent-pet
```

서명되고 Apple notarization을 통과한 DMG도 GitHub Releases에서 제공합니다. 움직이는 `main` 브랜치나 `curl | sh` 설치는 지원하지 않습니다.

CLI 이름은 `omapet`입니다.

현재 소스 빌드에서는 다음 CLI로 Claude Code와 Codex 연결을 관리할 수 있습니다. 이후 첫 실행 설정 UI도 같은 연결 엔진을 사용합니다.

```bash
omapet setup status --json
omapet setup status codex --json
omapet setup connect claude --dry-run --json
omapet setup connect claude
omapet setup disconnect claude
omapet setup connect codex --dry-run --json
omapet setup connect codex
omapet setup disconnect codex
```

`--dry-run`은 현재 설정과 예상 변경을 확인하고 파일을 수정하지 않습니다. 연결과 해제는 Oh My Agent Pet marker가 있는 hook만 대상으로 하며 다른 hook과 설정을 보존합니다. Codex 연결은 현재 설치된 Codex가 계산한 각 hook의 정확한 해시만 신뢰하고, 연결 해제 시 해당 신뢰 항목만 정리합니다.

## 업데이트

첫 안정 릴리스에서는 서명된 업데이트 피드를 확인하고 새 버전과 릴리스 노트를 표시할 예정입니다. 업데이트 설치는 사용자가 선택할 때 진행하며, 자동 확인은 설정에서 끌 수 있게 합니다. beta 버전은 명시적으로 채널을 선택한 사용자에게만 표시합니다.

Homebrew Cask도 앱이 자체 업데이트할 수 있는 패키지로 표시하고, Homebrew로 직접 갱신하는 경로를 함께 제공할 예정입니다. Sparkle 업데이트는 현재 구현 전입니다.

## 개인정보

Oh My Agent Pet은 사용량 telemetry를 전송하지 않으며 프롬프트, 도구 입력 및 출력과 내부 추론을 복사하거나 저장하지 않습니다. 자세한 내용은 [PRIVACY.md](PRIVACY.md)를 확인하세요.

## 라이선스

소스 코드는 [MIT License](LICENSE)로 배포합니다. 외부 의존성과 번들 자산의 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에서 관리합니다. 사용자가 별도로 설치한 펫은 각 자산의 원래 라이선스와 배포 조건을 따릅니다.
