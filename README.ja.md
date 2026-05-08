<p align="center">
  <img src="docs/assets/codexy-pet-usages-ring-titlebar.png" alt="Codexy pet usages ring GitHub title bar" width="100%">
</p>

<p align="center">
  <a href="https://github.com/himomohi/Codexy-pet-usages-ring/releases/latest">
    <img alt="Download latest release" src="https://img.shields.io/badge/Download_latest_release-v0.1.5-3CEBBD?style=for-the-badge&logo=github">
  </a>
</p>

<p align="center">
  <a href="CHANGELOG.md#015"><img alt="Version 0.1.5" src="https://img.shields.io/badge/version-0.1.5-3CEBBD?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-56B2FF?style=for-the-badge"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=for-the-badge">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-3CEBBD?style=for-the-badge">
</p>

<p align="center">
  <a href="#クイックスタート">クイックスタート</a>
  · <a href="#コマンド">コマンド</a>
  · <a href="#プライバシー">プライバシー</a>
  · <a href="README.md">English</a>
  · <a href="README.ko.md">한국어</a>
  · <span>日本語</span>
  · <a href="README.zh.md">中文</a>
</p>

Codexy pet usages ring は、Codex Desktop の `/pet` アバターの周囲に
半透明の使用量リングを表示する companion overlay です。
[petergpt/codex-pet-limit-rings](https://github.com/petergpt/codex-pet-limit-rings)
の companion-app 方式を、Windows 向けに PowerShell、WPF、Win32 のウィンドウ制御で実装しています。

<p align="center">
  <a href="docs/assets/usage-rec.mp4">
    <img src="docs/assets/usage-rec.gif" alt="Codexy pet usage rings demo" width="100%">
  </a>
</p>

<p align="center">
  数分おきに使用量ページを確認するのはやめましょう。<br>
  代わりに pet に知らせてもらえます。
</p>

<!-- Features -->

## 機能

- 現在の Codex `/pet` アバターの周囲に円形リングまたは小さなバッテリーバーを表示します。
- ホバー時に 5h 制限と週間制限の使用量を表示します。
- readout、tray text、設定 UI を英語、韓国語、日本語、中国語にローカライズします。
- Codex Desktop を自動検出し、必要に応じて起動できます。
- `/pet` が表示されるまで静かに待機します。
- WPF ベースの click-through overlay なので、マウス入力を奪いません。
- Windows スタートアップとスタートメニューのショートカットを作成できます。
- ルートの `.bat` launcher から、インストール、設定、状態確認、開始、停止、アンインストールをダブルクリックで実行できます。

<!-- Requirements -->

## 要件

- Windows 10 または Windows 11。
- Codex Desktop がインストール済みで、サインイン済みであること。
- PowerShell 5.1 以上。
- リングを表示するには Codex `/pet` overlay が開いている必要があります。

Python は任意で、ローカル SQLite log fallback にのみ使用されます。

<!-- Quick Start -->

## クイックスタート

1. この repository をダウンロードまたは clone します。
2. repository フォルダーを開きます。
3. `Install.bat` をダブルクリックします。
4. Codex Desktop で `/pet` を使用します。

Installer はファイルを `%LOCALAPPDATA%\CodexPetLimitRingsWin` にコピーし、
helper を開始して Windows スタートアップに登録します。

PowerShell でのインストール:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

## コマンド

ダブルクリック用 launcher:

```text
Install.bat
Start.bat
Stop.bat
Status.bat
Settings.bat
Uninstall.bat
```

インストール済みの場合、launcher は `%LOCALAPPDATA%\CodexPetLimitRingsWin`
配下のインストール済み helper を自動的に使用します。

PowerShell:

```powershell
.\bin\powershell\Start.ps1
.\bin\powershell\Stop.ps1
.\bin\powershell\Status.ps1
.\bin\powershell\Settings.ps1
.\bin\powershell\Diagnose.ps1
.\bin\powershell\Uninstall.ps1
```

よく使うインストールオプション:

```powershell
.\bin\powershell\Install.ps1 -NoStartCodex
.\bin\powershell\Install.ps1 -NoStartup -NoStartMenu -NoStart
.\bin\powershell\Install.ps1 -NoLiveUsage
```

インストール済みファイルも削除する場合:

```powershell
.\bin\powershell\Uninstall.ps1 -RemoveFiles
```

`-RemoveFiles` は、誤ったフォルダーを再帰削除しないように、対象ディレクトリに
install marker がある場合のみ動作します。

## カスタマイズ

`Settings.bat` を開くか、次のコマンドを実行します:

```powershell
.\bin\powershell\Settings.ps1
```

設定ファイル:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\settings.json
```

リング/バッテリー表示を選び、色、不透明度、readout 色、hover text サイズを
変更できます。実行中の
helper は設定ファイルの変更を自動的に再読み込みします。

## プライバシー

この app は次のローカル Codex ファイルを読み取ります:

- `%USERPROFILE%\.codex\.codex-global-state.json`
- `%USERPROFILE%\.codex\auth.json`
- `%USERPROFILE%\.codex\logs_2.sqlite` または `logs_1.sqlite`

OpenAI API key は不要です。pet 画像、スクリーンショット、prompt、repository
内容、spritesheet は送信しません。

Live usage はローカル Codex access token を次の URL にのみ使用します:

```text
https://chatgpt.com/backend-api/wham/usage
```

ネットワーク live usage は `-NoLiveUsage` で無効化できます。

設定ページは random session token 付きの一時的な `127.0.0.1` server を使用し、
ローカルの `settings.json` ファイルだけを書き込みます。

## 注意

- これは OpenAI または Codex の公式機能ではありません。
- Live usage endpoint は文書化された third-party API ではないため、変更される可能性があります。
- リングは `/pet` が開いている間だけ表示されます。

## AI インストール引き継ぎ

Repository URL:

```text
https://github.com/himomohi/Codexy-pet-usages-ring
```

AI agent に次の repository URL を渡して、Windows へのインストールを依頼できます:

```text
Install Codexy pet usages ring from:
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

## もっと見る

- [CHANGELOG.md](CHANGELOG.md)
- [SECURITY.md](SECURITY.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
- [docs/architecture.md](docs/architecture.md)
- [NOTICE.md](NOTICE.md)

Release zip を作成:

```powershell
.\tools\New-ReleaseZip.ps1
```

機能追加や bug fix release では、`VERSION`、README badge、`CHANGELOG.md` の
最上位バージョンを一緒に更新してください。
