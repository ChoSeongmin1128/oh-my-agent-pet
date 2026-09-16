# Oh My Agent Pet

Oh My Agent Pet은 Claude Code와 Codex 작업 상태를 한 마리의 macOS 데스크톱 펫으로 보여주는 독립 오픈소스 앱입니다.

현재 첫 릴리스를 설계하고 있으며 아직 설치 가능한 버전은 없습니다.

## 예정 기능

- Claude Code와 Codex 작업 상태 통합
- 한 마리의 펫으로 작업 중, 입력 필요, 실패와 완료 표현
- 작업 카드를 눌러 정확한 앱, 창과 터미널 세션으로 이동
- 카드 내용, 펫 움직임, 시선과 표시 방식 사용자 설정
- Claude만 사용하는 구성 지원
- 사용자 펫과 Codex 호환 펫 포맷 지원
- 로컬 진단 창과 명시적인 진단 자료 내보내기

지원 예정 환경은 macOS 14 이상입니다.

## 설치

첫 안정 릴리스 이후 Homebrew Cask를 기본 설치 경로로 제공합니다.

```bash
brew install --cask choseongmin1128/tap/oh-my-agent-pet
```

서명되고 Apple notarization을 통과한 DMG도 GitHub Releases에서 제공합니다. 움직이는 `main` 브랜치나 `curl | sh` 설치는 지원하지 않습니다.

CLI 이름은 `omapet`입니다.

## 개인정보

Oh My Agent Pet은 사용량 telemetry를 전송하지 않으며 프롬프트, 도구 입력 및 출력과 내부 추론을 복사하거나 저장하지 않습니다. 자세한 내용은 [PRIVACY.md](PRIVACY.md)를 확인하세요.

## 라이선스

소스 코드는 [MIT License](LICENSE)로 배포합니다. 외부 의존성과 번들 자산의 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에서 관리합니다. 사용자가 별도로 설치한 펫은 각 자산의 원래 라이선스와 배포 조건을 따릅니다.
