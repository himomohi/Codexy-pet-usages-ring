# Codex Pet Limit Rings for Windows

Codex `/pet` 아바타 주변에 반투명 사용량 링을 표시하는 Windows용 companion overlay입니다.

이 프로젝트는
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings)
의 companion-app 방식을 Windows 환경에 맞게 PowerShell, WPF, Win32 창 제어로 구현한 버전입니다.

[English README](README.md)

## 기능

- 현재 보이는 Codex `/pet` 아바타 주변에 완전한 원형 링을 표시합니다.
- 설치된 Codex Desktop 앱 경로를 자동으로 찾고, helper가 시작될 때 Codex를 함께 실행합니다.
- `/pet`가 아직 꺼져 있으면 자동으로 기다렸다가, 펫 오버레이가 열릴 때 링을 표시합니다.
- 링 창을 Codex 아바타 오버레이 뒤에 배치해 펫과 상단 메시지가 앞에 보이도록 합니다.
- 링별 hover readout을 표시합니다. 바깥 링은 5h 한도, 안쪽 링은 주간 한도입니다.
- WPF 기반 반투명 click-through 창을 사용하므로 마우스 입력을 가로채지 않습니다.
- `%USERPROFILE%\.codex\.codex-global-state.json`에서 `/pet` 위치를 읽습니다.
- `auth.json`의 로컬 Codex 토큰으로 `https://chatgpt.com/backend-api/wham/usage`에서 live usage를 읽습니다.
- Python과 Codex 로그가 있으면 최근 `codex.rate_limits` 로그를 fallback으로 사용합니다.
- `%LOCALAPPDATA%\CodexPetLimitRingsWin`에 설치하고 Windows 시작프로그램에 등록할 수 있습니다.

## 하지 않는 것

- Codex Desktop 앱을 패치하지 않습니다.
- `pet.json`, `spritesheet.webp`, pet 패키지를 수정하지 않습니다.
- 중복 pet을 만들지 않습니다.
- 메시지를 피하려고 링을 잘라내지 않습니다. 링은 항상 완전한 원형입니다.
- OpenAI 또는 Codex의 공식 기능은 아닙니다.

## 라이선스와 출처 / License And Attribution

이 Windows 프로젝트는 MIT License로 배포된
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings)
의 derivative/fork입니다.

원본 MIT 저작권 고지는 [LICENSE](LICENSE)에 Windows 프로젝트 고지와 함께
보존했습니다. 추가 출처 표기는 [NOTICE.md](NOTICE.md)에 남겨두었습니다.

## 요구 사항

- Windows 10 또는 Windows 11.
- Codex Desktop 설치 및 로그인. Store/AppX 설치 경로는 installer가 자동으로 찾습니다.
- PowerShell 5.1 이상. 기본 Windows PowerShell이면 충분합니다.
- 링이 보이려면 Codex `/pet` 오버레이가 열려 있어야 합니다.

Python은 선택 사항입니다. 로컬 SQLite 로그 fallback에만 사용됩니다. Live usage는 Python이 필요 없습니다.

## 빠른 시작

링을 설치하고 시작프로그램에 등록합니다:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

Installer가 Codex Desktop을 자동으로 찾아 실행을 시도합니다. 그 다음 `/pet`를
평소처럼 사용하면 됩니다. pet별 추가 설정은 필요 없습니다. ring 앱이 `/pet`보다
먼저 켜져 있어도 그냥 기다리다가 `/pet`가 열리는 순간 자동으로 표시됩니다.

설치 없이 실행:

```powershell
.\bin\powershell\Start.ps1
```

설치된 항목 제거:

```powershell
.\bin\powershell\Uninstall.ps1
```

## 설치

사용 중인 터미널에 맞는 명령을 실행하면 됩니다.

PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

Windows CMD:

```bat
bin\cmd\install.cmd
```

Git Bash, MSYS, Cygwin, 또는 Windows의 WSL:

```sh
sh ./bin/bash/install.sh
```

설치 위치:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin
```

설치 시 생성되는 항목:

- Windows 시작프로그램 shortcut
- 시작 메뉴 shortcut
- 숨겨진 background ring process

설치 시와 이후 helper 시작 시마다 Codex Desktop을 자동 탐색합니다. 탐색 순서는
실행 중인 `Codex.exe`, `OpenAI.Codex` AppX package, 시작 메뉴 AppID,
`WindowsApps` 후보 폴더입니다. 발견되면 ring helper를 띄우기 전에 Codex Desktop을
먼저 시작합니다.

Codex Desktop 자동 시작을 끄려면:

```powershell
.\bin\powershell\Install.ps1 -NoStartCodex
```

자동 탐색이 부족한 PC에서는 Codex Desktop path 또는 AppID를 직접 지정할 수 있습니다:

```powershell
.\bin\powershell\Install.ps1 -CodexAppPath "C:\Program Files\WindowsApps\OpenAI.Codex_...\app\Codex.exe"
.\bin\powershell\Install.ps1 -CodexAppId "OpenAI.Codex_2p2nqsd0c76g0!App"
```

Shortcut 없이 portable install만 하려면:

```powershell
.\bin\powershell\Install.ps1 -NoStartup -NoStartMenu -NoStart
```

같은 옵션은 CMD와 Bash wrapper로도 넘길 수 있습니다:

```bat
bin\cmd\install.cmd -NoStartup -NoStartMenu -NoStart
```

```sh
sh ./bin/bash/install.sh -NoStartup -NoStartMenu -NoStart
```

## 시작, 중지, 상태 확인

PowerShell:

```powershell
.\bin\powershell\Start.ps1
.\bin\powershell\Stop.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Settings.ps1
```

Windows CMD:

```bat
bin\cmd\start.cmd
bin\cmd\stop.cmd
bin\cmd\status.cmd
bin\cmd\settings.cmd
```

Bash:

```sh
sh ./bin/bash/start.sh
sh ./bin/bash/stop.sh
sh ./bin/bash/status.sh
sh ./bin/bash/settings.sh
```

## 커스터마이즈 / Customize

HTML 설정 페이지를 엽니다:

```powershell
.\bin\powershell\Settings.ps1
```

설정 UI는 `127.0.0.1`에서만 임시로 실행되고 아래 파일에 저장합니다:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\settings.json
```

실행 중인 ring helper는 `settings.json` 변경을 자동으로 다시 읽습니다. 우선 지원하는
항목은 다음입니다:

- ring colors: 바깥 5h, 안쪽 weekly, warning, caution, track
- readout colors: text, tooltip backgrounds
- opacity: rings, track, readout background, readout text
- text: hover readout font size, line height

## 자동 감지

Background app은 `/pet`가 닫혀 있어도 계속 실행됩니다. 시작 시 `-NoStartCodex`를
쓰지 않았다면 Codex Desktop을 자동 탐색하고 실행합니다. 이후 기본값으로 300ms마다
Codex Desktop의 avatar overlay state를 확인하고, `/pet`가 닫혀 있으면 링을 숨긴
뒤 `/pet`가 다시 열리면 자동으로 표시합니다. 그래서 Windows 로그인 때 앱이 먼저
실행되고 Codex 또는 `/pet`가 나중에 열려도 괜찮습니다.

사용량 값은 기본값으로 10초마다 확인합니다. 새 값이 들어오면 링은 꺼지지 않고
일반 frame loop에서 새 퍼센트까지 부드럽게 변화합니다. usage 요청이 실패해도
마지막으로 알던 값은 화면에 남고, 링을 지우거나 숨기지 않습니다.

CPU와 메모리를 적게 쓰도록 animation loop와 `/pet` 감지를 분리했습니다. Codex
state file은 수정 시간이 바뀐 경우에만 다시 파싱하고, pet bounds 또는 표시 usage가
실제로 바뀔 때만 ring geometry를 다시 그립니다. `/pet`가 닫혀 있으면 animation loop도
멈춥니다. 아무 변화가 없을 때는 느린 idle cadence로 동작하고, gauge가 새 값으로
움직이는 동안에만 잠깐 빨라집니다. Helper process는 below-normal priority로 실행되고,
시작 후 working set을 한 번 정리한 뒤 긴 세션에서는 가끔만 다시 정리합니다.

바깥 링 근처에 마우스를 올리면 5h 한도의 퍼센트와 초기화 시간이 표시됩니다.
안쪽 링 근처에 마우스를 올리면 주간 한도의 퍼센트와 초기화 시간이 표시됩니다.
초기화 시간은 Windows 로컬 시간대를 기준으로 하며, usage source가 reset metadata를
제공하는 경우 남은 시간과 실제 시각을 함께 표시합니다.

아래 로그에서 동작을 확인할 수 있습니다:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\logs\rings.log
```

확인할 문구:

```text
Codex /pet overlay is not visible; waiting automatically.
Codex /pet overlay detected; showing rings.
```

진단:

```powershell
.\bin\powershell\Diagnose.ps1
```

Live usage endpoint까지 테스트:

```powershell
.\bin\powershell\Diagnose.ps1 -TestLiveUsage
```

## 제거

shortcut 제거 및 background process 중지:

```powershell
.\bin\powershell\Uninstall.ps1
```

설치 파일까지 제거:

```powershell
.\bin\powershell\Uninstall.ps1 -RemoveFiles
```

## 데이터와 개인정보

앱은 아래 로컬 Codex 파일을 읽습니다:

- `%USERPROFILE%\.codex\.codex-global-state.json`
- `%USERPROFILE%\.codex\auth.json`
- `%USERPROFILE%\.codex\logs_2.sqlite` 또는 `logs_1.sqlite`

OpenAI API key는 필요하지 않습니다. pet 이미지, 스크린샷, 프롬프트, 저장소 내용,
spritesheet는 어디에도 전송하지 않습니다.

설정 페이지는 `127.0.0.1`에 묶인 임시 local server만 사용하고 로컬 `settings.json`
파일만 씁니다. 설정값은 원격 서버로 전송하지 않습니다.

Live usage를 사용할 때 로컬 Codex access token은 아래 주소로만 전송됩니다:

```text
https://chatgpt.com/backend-api/wham/usage
```

네트워크 live usage를 끄려면:

```powershell
.\bin\powershell\Install.ps1 -NoLiveUsage
.\bin\powershell\Start.ps1 -NoLiveUsage
```

이 경우 local log fallback을 시도합니다. 유효한 로컬 rate-limit 이벤트가 없으면 링은 보이지만 최신 사용량 값은 표시되지 않을 수 있습니다.

## 프로젝트 구조 / Project Shape

```text
codex-pet-limit-rings-Win/
  README.md
  README.ko.md
  CHANGELOG.md
  LICENSE
  NOTICE.md
  VERSION
  settings.defaults.json
  settings/
    index.html
  bin/
    powershell/
      Install.ps1
      Start.ps1
      Stop.ps1
      Status.ps1
      Settings.ps1
      Diagnose.ps1
      Uninstall.ps1
    cmd/
      install.cmd
      start.cmd
      stop.cmd
      status.cmd
      settings.cmd
      diagnose.cmd
      uninstall.cmd
    bash/
      install.sh
      start.sh
      stop.sh
      status.sh
      settings.sh
      diagnose.sh
      uninstall.sh
  src/
    CodexAppDiscovery.ps1
    CodexPetLimitRings.ps1
  docs/
    architecture.md
    troubleshooting.md
  tools/
    New-ReleaseZip.ps1
  SECURITY.md
```

## Release zip 만들기

```powershell
.\tools\New-ReleaseZip.ps1
```

결과물은 `dist/`에 생성됩니다.

## 알려진 한계

- 현재 Codex는 이 overlay가 사용할 수 있는 공식 public usage-limit API를 제공하지 않습니다.
- Live usage endpoint는 문서화된 외부 API가 아니므로 변경될 수 있습니다.
- Codex Desktop이 저장하는 avatar bounds state 형식이 바뀌면 업데이트가 필요할 수 있습니다.
- 링은 `/pet`가 열려 있을 때만 보입니다.

## 문제 해결

[docs/troubleshooting.md](docs/troubleshooting.md)를 참고하세요.
