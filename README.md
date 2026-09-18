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
- 대표 작업 메뉴 행에서 Codex·Claude Desktop 대화, iTerm 세션 또는 Terminal 탭으로 이동
- 포커스를 빼앗지 않는 데스크톱 펫과 대표 작업 카드, 한 개·전체·없음 표시 모드
- 펫·카드 함께 드래그, 위치 저장·초기화와 전체 작업 임시 펼치기
- 기본 위아래 배치와 나란히 배치 선택, 한 개 모드의 추가 작업 겹침 표시 설정
- 설정 창의 일반·펫·카드 pane과 메뉴의 `Settings…`
- 사용자 펫 라이브러리: package folder, codex-pet ZIP과 codex-pets.net 링크 설치, 선택, 제거와 라이선스·출처 표시
- 앱과 같은 라이브러리를 쓰는 `omapet pet` CLI
- Apple Silicon과 Intel을 함께 검증하는 GitHub Actions CI

현재 소스 코드는 앱 기반과 Claude·Codex 상태 관찰, CLI 연결, 대표 작업 이동, 펫·카드 화면, 카드 배치·겹침 설정, codex-pets 스프라이트 엔진과 사용자 펫 라이브러리까지 구현한 개발 버전입니다. 완료 확인, 연동·개인정보 설정 pane과 서명된 업데이트는 아직 구현 중입니다.

## 펫과 작업 카드

새 실행에서는 한 마리의 펫과 대표 작업 카드 한 개를 위아래로 표시합니다. Card 설정에서 펫 왼쪽·카드 오른쪽의 나란히 배치로 바꿀 수 있습니다. 한 개 모드에서는 다른 작업이 있음을 보여주는 얕은 카드 겹침 표시가 기본으로 켜지며 설정에서 끌 수 있습니다. 메뉴바에서 카드를 한 개, 전체 또는 표시 안 함으로 바꿀 수 있으며 선택은 다음 실행에도 유지됩니다. 펫을 빠르게 클릭하면 저장한 모드와 전체 작업 목록을 임시로 전환합니다. 펫이나 카드를 드래그하면 함께 이동하고 메뉴의 `Reset Pet Position`으로 기본 위치를 복원할 수 있습니다.

기본 펫은 프로젝트 코드로 그리는 원본 벡터 펫입니다. codex-pets v1·v2 패키지를 설치하면 상태별 애니메이션과 v2 마우스 시선을 사용합니다.

## 펫 라이브러리

메뉴의 `Settings…`로 설정 창을 열고 `Pet` pane에서 펫을 관리합니다.

- `Add Pet…`으로 `pet.json`과 spritesheet가 있는 package folder 또는 codex-pet ZIP을 고르거나, `Add from Link…`에 `https://codex-pets.net/#/pets/<id>` 링크를 붙입니다. 링크 다운로드는 `Continue`를 눌렀을 때만 시작합니다.
- 설치 전 검토 화면에서 이름, 출처, 라이선스 상태와 실제 상태별 애니메이션을 확인하고 `Install` 또는 `Install and Use`를 선택합니다.
- 목록에서 원본 벡터 펫, 설치한 펫, `No pet`을 `Use`로 선택합니다. `No pet`은 펫만 숨기고 카드와 메뉴바는 유지하며, 작업이 여러 개일 때 카드 위의 작은 화살표로 전체 작업을 펼칩니다.
- 보조 메뉴에서 Finder 표시, 정보 보기, 제거를 사용합니다. 제거는 앱 라이브러리 사본만 지우고 원본 folder, ZIP과 갤러리 펫은 바꾸지 않습니다.
- 라이선스는 `License declared`(package나 매니페스트가 표기), `No license info`(표기 없음)로 구분합니다. 표기가 없어도 로컬 설치는 가능하지만 Oh My Agent Pet이 재배포 권한을 주는 것은 아니며, 설치한 펫은 프로젝트 MIT License로 바뀌지 않습니다.
- 선택한 펫이 손상되거나 사라지면 원본 벡터 펫으로 돌아가고 설정에 조치 필요를 표시합니다.

단독 PNG/WebP 이미지는 버전·이름·출처를 판정할 수 없어 받지 않습니다. 설치한 펫은 `~/Library/Application Support/Oh My Agent Pet/Pets`에 복사되고, 선택은 같은 위치의 `selection.json`에 저장되어 CLI와 앱이 공유합니다.

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
omapet doctor --json
```

`--dry-run`은 현재 설정과 예상 변경을 확인하고 파일을 수정하지 않습니다. 연결과 해제는 Oh My Agent Pet marker가 있는 hook만 대상으로 하며 다른 hook과 설정을 보존합니다. Codex 연결은 현재 설치된 Codex가 계산한 각 hook의 정확한 해시만 신뢰하고, 연결 해제 시 해당 신뢰 항목만 정리합니다. `doctor`는 설정을 변경하지 않고 Claude·Codex 연결 상태, 저장된 펫 선택과 로컬 이벤트 파일의 기본 안전 상태를 검사합니다.

펫 라이브러리는 설정 창과 같은 서비스를 CLI로도 제공합니다.

```bash
omapet pet list --json
omapet pet inspect <package-folder|codex-pet.zip|https://codex-pets.net/#/pets/ID> --json
omapet pet install <package-folder|codex-pet.zip|https://codex-pets.net/#/pets/ID> --dry-run --json
omapet pet install <package-folder|codex-pet.zip|https://codex-pets.net/#/pets/ID> --json
omapet pet select <original|none|pet-id> --json
omapet pet remove <pet-id> --json
```

`inspect`와 `install --dry-run`은 라이브러리와 선택을 바꾸지 않습니다. 오류는 `unsupported_version`, `version_dimension_mismatch`, `missing_required_frame`, `damaged_image`, `unsafe_package`, `oversized_package`, `url_not_allowed`처럼 안정적인 코드로 반환하며 설정 창도 같은 코드를 사용합니다. URL은 `https://codex-pets.net`만 지원하고 같은 host 안의 redirect만 최대 3회 따라갑니다.

## 작업으로 돌아가기

현재 메뉴의 대표 작업 행을 누르면 실행 위치에 따라 다음 경로를 사용합니다.

- Codex Desktop: 해당 thread deep link
- Claude Desktop Code: 로컬 session deep link
- iTerm2: hook에서 받은 `ITERM_SESSION_ID`를 사용하는 공식 reveal URL
- Terminal.app: hook에서 받은 TTY와 일치하는 창과 탭 선택

iTerm2 이동에는 Automation 권한이 필요하지 않습니다. Terminal.app은 처음 정확한 탭 이동을 사용할 때 Automation 권한을 요청할 수 있습니다. 권한이 없거나 정확한 대상이 사라졌으면 새 세션을 만들지 않고 원래 앱만 활성화하며, 메뉴에 부분 성공 또는 실패를 표시합니다.

## 업데이트

첫 안정 릴리스에서는 서명된 업데이트 피드를 확인하고 새 버전과 릴리스 노트를 표시할 예정입니다. 업데이트 설치는 사용자가 선택할 때 진행하며, 자동 확인은 설정에서 끌 수 있게 합니다. beta 버전은 명시적으로 채널을 선택한 사용자에게만 표시합니다.

Homebrew Cask도 앱이 자체 업데이트할 수 있는 패키지로 표시하고, Homebrew로 직접 갱신하는 경로를 함께 제공할 예정입니다. Sparkle 업데이트는 현재 구현 전입니다.

## 개인정보

Oh My Agent Pet은 사용량 telemetry를 전송하지 않으며 프롬프트, 도구 입력 및 출력과 내부 추론을 복사하거나 저장하지 않습니다. 자세한 내용은 [PRIVACY.md](PRIVACY.md)를 확인하세요.

## 라이선스

소스 코드는 [MIT License](LICENSE)로 배포합니다. 외부 의존성과 번들 자산의 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에서 관리합니다. 사용자가 별도로 설치한 펫은 각 자산의 원래 라이선스와 배포 조건을 따릅니다.
