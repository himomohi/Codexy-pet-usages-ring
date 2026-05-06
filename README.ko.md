<p align="center">
  <img src="docs/assets/codex-pet-limit-rings-win-titlebar.png" alt="Codex Pet Limit Rings for Windows GitHub title bar" width="100%">
</p>

<p align="center">
  <a href="CHANGELOG.md#013"><img alt="Version 0.1.3" src="https://img.shields.io/badge/version-0.1.3-3CEBBD?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-56B2FF?style=for-the-badge"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=for-the-badge">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-3CEBBD?style=for-the-badge">
</p>

<p align="center">
  <a href="#빠른-시작">빠른 시작</a>
  · <a href="#명령">명령</a>
  · <a href="#개인정보">개인정보</a>
  · <a href="README.md">English</a>
</p>

Codex Pet Limit Rings for Windows는 Codex Desktop `/pet` 아바타 주변에 반투명
사용량 링을 표시하는 companion overlay입니다.
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings)
의 companion-app 방식을 Windows용 PowerShell, WPF, Win32 창 제어로 구현했습니다.

## 기능

- 현재 Codex `/pet` 아바타 뒤에 완전한 원형 링을 표시합니다.
- 바깥 링은 5h 한도, 안쪽 링은 주간 한도를 hover readout으로 보여줍니다.
- Codex Desktop을 자동 감지하고 필요하면 실행합니다.
- `/pet`가 보일 때까지 조용히 대기합니다.
- WPF 기반 click-through overlay라서 마우스 입력을 가로채지 않습니다.
- Windows 시작프로그램과 시작 메뉴 shortcut을 만들 수 있습니다.
- 루트 `.bat` 파일로 설치, 설정, 상태 확인, 시작, 중지, 제거를 더블클릭 실행할 수 있습니다.

## 요구 사항

- Windows 10 또는 Windows 11.
- Codex Desktop 설치 및 로그인.
- PowerShell 5.1 이상.
- 링이 보이려면 Codex `/pet` 오버레이가 열려 있어야 합니다.

Python은 선택 사항이며 로컬 SQLite 로그 fallback에만 사용됩니다.

## 빠른 시작

1. 이 repository를 다운로드하거나 clone합니다.
2. repository 폴더를 엽니다.
3. `Install.bat`을 더블클릭합니다.
4. Codex Desktop에서 `/pet`를 사용합니다.

Installer는 파일을 `%LOCALAPPDATA%\CodexPetLimitRingsWin`에 복사하고 helper를
시작한 뒤 Windows 시작프로그램에 등록합니다.

PowerShell 설치:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

## 명령

더블클릭 launcher:

```text
Install.bat
Start.bat
Stop.bat
Status.bat
Settings.bat
Uninstall.bat
```

설치본이 있으면 launcher는 자동으로
`%LOCALAPPDATA%\CodexPetLimitRingsWin` 아래의 설치된 helper를 사용합니다.

PowerShell:

```powershell
.\bin\powershell\Start.ps1
.\bin\powershell\Stop.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Settings.ps1
.\bin\powershell\Diagnose.ps1
.\bin\powershell\Uninstall.ps1
```

자주 쓰는 설치 옵션:

```powershell
.\bin\powershell\Install.ps1 -NoStartCodex
.\bin\powershell\Install.ps1 -NoStartup -NoStartMenu -NoStart
.\bin\powershell\Install.ps1 -NoLiveUsage
```

설치 파일까지 제거:

```powershell
.\bin\powershell\Uninstall.ps1 -RemoveFiles
```

`-RemoveFiles`는 대상 폴더에 install marker가 있을 때만 동작해서 잘못된 폴더의
재귀 삭제를 막습니다.

## 커스터마이즈

`Settings.bat`을 열거나 아래 명령을 실행하세요:

```powershell
.\bin\powershell\Settings.ps1
```

설정 파일:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\settings.json
```

링 색상, 투명도, readout 색상, hover text 크기를 바꿀 수 있습니다. 실행 중인
helper는 설정 파일 변경을 자동으로 다시 읽습니다.

## 개인정보

앱은 아래 로컬 Codex 파일을 읽습니다:

- `%USERPROFILE%\.codex\.codex-global-state.json`
- `%USERPROFILE%\.codex\auth.json`
- `%USERPROFILE%\.codex\logs_2.sqlite` 또는 `logs_1.sqlite`

OpenAI API key는 필요하지 않습니다. pet 이미지, 스크린샷, 프롬프트, repository
내용, spritesheet는 전송하지 않습니다.

Live usage는 로컬 Codex access token을 아래 주소에만 사용합니다:

```text
https://chatgpt.com/backend-api/wham/usage
```

네트워크 live usage는 `-NoLiveUsage`로 끌 수 있습니다.

설정 페이지는 random session token이 있는 임시 `127.0.0.1` 서버를 사용하고,
로컬 `settings.json` 파일만 씁니다.

## 주의

- OpenAI 또는 Codex의 공식 기능이 아닙니다.
- Live usage endpoint는 문서화된 외부 API가 아니므로 바뀔 수 있습니다.
- 링은 `/pet`가 열려 있을 때만 보입니다.

## AI 설치 지시

Repository URL:

```text
https://github.com/himomohi/Codexy-pet-usages-ring
```

AI agent에게 아래 repository URL과 함께 Windows 설치를 요청하세요:

```text
Install Codex Pet Limit Rings for Windows from:
https://github.com/himomohi/Codexy-pet-usages-ring

If the repository is not local, clone it first. Then run Install.bat from the
repository root. After installation, run Status.ps1 and Diagnose.ps1 to verify
that the helper is installed, running, and waiting for or following /pet.
```

CLI equivalent:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Diagnose.ps1
```

## 더 보기

- [CHANGELOG.md](CHANGELOG.md)
- [SECURITY.md](SECURITY.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
- [docs/architecture.md](docs/architecture.md)
- [NOTICE.md](NOTICE.md)

Release zip 만들기:

```powershell
.\tools\New-ReleaseZip.ps1
```

기능 추가와 버그 수정 release는 `VERSION`, README badge, `CHANGELOG.md`의
최상단 버전을 함께 올립니다.
