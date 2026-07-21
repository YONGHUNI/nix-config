# nix-config

Personal NixOS configurations managed with flakes.

This repository currently manages two environments:

- **LG Gram (`gram`)**: NixOS desktop
- **WSL (`wsl`)**: existing NixOS-WSL development environment

System-wide settings and lightweight base tools belong in this repository. Project-specific dependencies such as NumPy, pandas, Jupyter, CUDA, and machine-learning libraries should remain in each project's `flake.nix`, `devShell`, or another local environment manager.

## Repository layout

```text
.
├── flake.nix
├── flake.lock
├── home/
│   └── yonghun.nix
├── hosts/
│   ├── gram/
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── wsl/
│       └── configuration.nix
└── pkgs/
    └── hop/
        └── default.nix
```

## Configuration overview

### LG Gram

- NixOS 26.05
- KDE Plasma desktop
- Home Manager
- Fcitx5 Korean input
- TPM2-based LUKS unlocking
- Flatpak and Bottles
- System Wine
- HOP HWP/HWPX editor
- Base desktop and command-line tools

### WSL

- NixOS-WSL
- NixOS 25.11 package set retained
- OpenSSH with Kerberos/GSSAPI
- Kerberos realm configuration for MPCDF
- Base command-line and development tools
- Automatic Nix store optimization and cleanup of old generations

## Common commands

### Gram

```bash
cd ~/nix-config

# Evaluate the flake
nix flake check

# Build without switching the active system generation
sudo nixos-rebuild build --flake .#gram

# Apply the configuration
sudo nixos-rebuild switch --flake .#gram
```

### WSL

```bash
cd ~/nix-config
sudo nixos-rebuild switch --flake .#wsl
```

### Update flake inputs

```bash
cd ~/nix-config
nix flake update
sudo nixos-rebuild switch --flake .#gram
```

Review `git diff flake.lock` before applying an input update.

## Deploying to a new system

### Gram

After installing NixOS:

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
cd ~/nix-config
sudo nixos-rebuild switch --flake .#gram
```

`hosts/gram/hardware-configuration.nix` contains disk, filesystem, and encrypted-volume settings for the current LG Gram. It must not be reused unchanged on another machine.

### WSL

```bash
git clone https://github.com/YONGHUNI/nix-config.git ~/nix-config
cd ~/nix-config
sudo nixos-rebuild switch --flake .#wsl
```

## Home Manager

User packages and user-level configuration are managed in `home/yonghun.nix`.

Current packages include:

```text
git
gh
htop
bat
wev
hop
```

The Fcitx5 input-method profile is also declared in this file.

---

# LG Gram 터치패드 Fn+F5 및 상태 LED

LG Gram에서 `Fn+F5`를 누르면 터치패드가 잠시 비활성화된 뒤 바로 다시 활성화되는 문제가 있었다.

원인은 다음과 같았다.

1. LG 펌웨어가 터치패드 상태를 전환한다.
2. `lg_laptop` 커널 모듈이 같은 키를 `KEY_F21` 이벤트로 전달한다.
3. KDE Plasma가 `KEY_F21`을 다시 처리하면서 터치패드 상태가 한 번 더 전환된다.

`lg_laptop` 모듈을 비활성화하면 문제는 사라지지만, 다음 LG 전용 기능도 사용할 수 없게 된다.

* 배터리 충전 제한
* 키보드 백라이트
* 터치패드 LED
* 팬 모드
* 리더 모드
* Fn Lock
* USB 충전 설정

따라서 `lg_laptop` 모듈은 유지하고, `Fn+F5` 이벤트만 사용하지 않는 `F24`로 재매핑했다.

### 시스템 설정

`hosts/gram/configuration.nix`:

```nix
# Remap the LG Fn+F5 hotkey from KEY_F21 to F24.
services.udev.extraHwdb = ''
  evdev:name:LG WMI hotkeys:*
   KEYBOARD_KEY_74=f24
'';

# Allow members of the users group to control the touchpad LED.
services.udev.extraRules = ''
  ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpad_led", RUN+="${pkgs.coreutils}/bin/chgrp users /sys%p/brightness"
  ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpad_led", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/brightness"
'';
```

### 사용자 설정

`home/yonghun.nix`에서는 `F24`를 Plasma 전역 단축키로 등록하고, 터치패드 LED 값을 `0`과 `1` 사이에서 전환하는 스크립트를 실행한다.

```nix
hotkeys.commands."toggle-touchpad-led" = {
  name = "Toggle touchpad LED";
  key = "F24";
  command = "${toggleTouchpadLed}/bin/toggle-touchpad-led";
};
```

### 확인

Fn+F5 입력 확인:

```bash
sudo evtest /dev/input/event6
```

정상 출력:

```text
KEY_F24
```

LED 상태 확인:

```bash
cat /sys/class/leds/tpad_led/brightness
```

`Fn+F5`를 누를 때 값이 `0`과 `1` 사이에서 전환되며, 터치패드 표시등도 함께 켜지고 꺼진다.



# HOP

[HOP](https://github.com/golbin/hop)은 HWP와 HWPX 문서를 열고 편집할 수 있는 오픈소스 데스크톱 프로그램입니다.

이 저장소에서는 공식 Linux `.deb` 파일을 Nix 패키지로 재포장합니다.

## 구성 위치

```text
pkgs/hop/default.nix
```

Home Manager에서는 다음처럼 불러옵니다.

```nix
let
  hop = pkgs.callPackage ../pkgs/hop { };
in
{
  home.packages = with pkgs; [
    hop
  ];
}
```

## 빌드와 실행

```bash
cd ~/nix-config

nix build --impure --expr \
  'with import <nixpkgs> {}; callPackage ./pkgs/hop {}'

./result/bin/hop-desktop
```

시스템에 적용한 뒤에는 다음 명령으로 실행합니다.

```bash
hop-desktop
```

## NixOS 런타임 처리

HOP은 Tauri와 WebKitGTK를 사용합니다. 공식 `.deb`를 단순히 압축 해제하는 것만으로는 NixOS에서 정상 실행되지 않았습니다.

### GStreamer `appsink`

초기 실행 시 다음 메시지가 나타났습니다.

```text
GStreamer element appsink not found. Please install it.
```

`appsink`는 `gst-plugins-base`의 `libgstapp.so`에 포함됩니다. HOP wrapper에서 다음 경로를 `GST_PLUGIN_SYSTEM_PATH_1_0`에 추가합니다.

```text
${gst_all_1.gst-plugins-base}/lib/gstreamer-1.0
```

### Wayland 렌더링 문제

KDE Wayland에서 실행하면 UI가 화면 왼쪽의 매우 좁은 영역으로 압축되어 표시되었습니다.

HOP만 XWayland와 WebKitGTK 우회 설정으로 실행하면 정상적으로 표시됩니다.

```text
GDK_BACKEND=x11
WEBKIT_DISABLE_DMABUF_RENDERER=1
WEBKIT_DISABLE_COMPOSITING_MODE=1
```

이 환경변수들은 `pkgs/hop/default.nix`의 wrapper에 적용되어 있으므로 일반 실행 시 직접 지정할 필요가 없습니다.

### GTK 파일 선택기 충돌

파일 열기 또는 다른 이름으로 저장을 실행할 때 GTK 파일 선택기가 나타나기 직전에 HOP이 `SIGABRT`로 종료되는 문제가 있었습니다.

충돌은 GTK 파일 선택기가 사용하는 GSettings schema와 dconf backend가 실행 환경에 노출되지 않아 발생했습니다.

다음 런타임 경로가 필요합니다.

* GTK3 GSettings schema
* `gsettings-desktop-schemas`
* dconf GIO module
* GdkPixbuf loader

이를 위해 패키지의 `nativeBuildInputs`에서 `makeWrapper` 대신 `wrapGAppsHook3`를 사용합니다.

```nix
nativeBuildInputs = [
  dpkg
  autoPatchelfHook
  wrapGAppsHook3
];
```

기존 HOP 전용 환경변수는 별도의 `wrapProgram`으로 다시 감싸지 않고 `gappsWrapperArgs`에 추가합니다.

```nix
preFixup = ''
  gappsWrapperArgs+=(
    --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gst_all_1.gst-plugins-base}/lib/gstreamer-1.0"
    --set GDK_BACKEND x11
    --set WEBKIT_DISABLE_DMABUF_RENDERER 1
    --set WEBKIT_DISABLE_COMPOSITING_MODE 1
  )
'';
```

정상 적용되면 실행 로그에서 다음과 같이 dconf backend와 GTK 파일 선택기 설정이 로드됩니다.

```text
Found default implementation dconf for ‘gsettings-backend’
watch_fast: "/org/gtk/settings/file-chooser/"
```


## 업데이트

새 버전이 공개되면 `pkgs/hop/default.nix`의 `version`과 `src.hash`를 갱신합니다.

```bash
nix store prefetch-file \
  "https://github.com/golbin/hop/releases/download/vVERSION/HOP-linux-x64.deb"
```

출력된 SRI 해시를 `src.hash`에 반영한 뒤 다시 빌드합니다.

---

# Bottles와 카카오톡

LG Gram의 NixOS 환경에서 **Flatpak + Bottles + sys-wine**으로 Windows용 카카오톡을 실행합니다.

## 구성 구조

```text
NixOS
└─ Flatpak
   └─ Bottles
      └─ kakaotalk Bottle
         └─ sys-wine
            └─ KakaoTalk.exe
```

- **Flatpak**: Bottles를 설치하고 샌드박스에서 실행
- **Bottles**: Windows 프로그램별 Wine 환경 관리
- **Bottle**: Bottles 안의 독립된 Windows 실행 환경
- **sys-wine**: NixOS에 설치한 Wine을 Bottles runner로 사용

## 선언적 설치

`flake.nix`에서 `nix-flatpak`을 사용합니다.

```nix
nix-flatpak = {
  url = "github:gmodena/nix-flatpak";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Gram 모듈 목록에는 다음을 포함합니다.

```nix
modules = [
  ./hosts/gram/configuration.nix
  home-manager.nixosModules.home-manager
  nix-flatpak.nixosModules.nix-flatpak
];
```

`hosts/gram/configuration.nix`에서 Wine과 Bottles를 선언합니다.

```nix
environment.systemPackages = with pkgs; [
  wineWowPackages.stable
];

services.flatpak = {
  enable = true;

  remotes = [
    {
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }
  ];

  packages = [
    "com.usebottles.bottles"
  ];

  update.auto.enable = false;
  uninstallUnmanaged = false;
};
```

적용:

```bash
cd ~/nix-config
nix flake check
sudo nixos-rebuild switch --flake .#gram
```

## Bottles 실행

```bash
flatpak run com.usebottles.bottles
```

설치 확인:

```bash
flatpak list --app | grep -i bottles
```

KDE 메뉴에 바로 나타나지 않으면:

```bash
kbuildsycoca6
```

## 카카오톡 Bottle 생성

권장값:

```text
Name: kakaotalk
Environment: Application
Architecture: 64-bit
Runner: sys-wine
```

Soda runner에서는 카카오톡 실행 시 다음 Themida 오류가 발생했습니다.

```text
An Error has occurred while loading imports. Wrong DLL present.
```

같은 Bottle에서 runner를 `sys-wine`으로 변경하면 실행됩니다.

## 카카오톡 설치

1. 카카오 공식 사이트에서 Windows 64비트 설치 파일을 다운로드합니다.
2. Bottles에서 `kakaotalk` Bottle을 엽니다.
3. `Run Executable...`을 선택합니다.
4. `KakaoTalk_Setup.exe`를 실행합니다.
5. 일반 Windows 설치 절차대로 설치합니다.

`Install Programs...`는 Bottles의 커뮤니티 설치 목록이므로 카카오톡 설치에는 사용하지 않습니다.

설치 후 설치 파일은 삭제해도 됩니다.

```bash
rm ~/Downloads/KakaoTalk_Setup.exe
```

## 한글 폰트

한글이 `□□□`처럼 표시되면 Bottle에 CJK 글꼴을 설치합니다.

```text
kakaotalk Bottle
→ Dependencies
→ cjkfonts
```

설치 후 카카오톡 설치 프로그램 또는 카카오톡을 완전히 종료하고 다시 실행합니다.

## 한글 입력

Bottle 환경변수에 다음 하나만 추가합니다.

```text
XMODIFIERS=@im=fcitx
```

경로:

```text
kakaotalk Bottle
→ Settings
→ Environment Variables
```

현재 구성에서는 다음 변수가 필요하지 않았습니다.

```text
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
SDL_IM_MODULE=fcitx
FCITX_XIM_IBUS=1
```

특히 `FCITX_XIM_IBUS=1`을 추가하면 카카오톡에서 한글 입력이 다시 작동하지 않았습니다.

### 파란 preedit 상자

한글 조합 중 파란 preedit 상자가 나타납니다. 이는 Wine이 Fcitx5의 XIM 입력을 처리하는 방식에서 발생합니다.

- `XMODIFIERS=@im=fcitx`만 유지하면 입력은 정상 동작합니다.
- Wine의 실험적 Wayland 드라이버에서는 inline 조합이 가능했지만 작은 보조 창이 나타났습니다.
- 안정성을 위해 Wayland 옵션을 끄고 기본 XWayland/XIM 방식을 사용합니다.

## 권장 Bottle 설정

### Components

```text
Runner: sys-wine-11.0
DXVK: Disabled
VKD3D: Disabled
LatencyFleX: Disabled
```

### Display

```text
Discrete Graphics: Off
Wayland (Experimental): Off
Post-Processing Effects: Off
Gamescope: Off
```

### Performance

```text
Synchronization: System
Monitor Performance: Off
Feral GameMode: Off
Preload Game Files: Off
OBS Game Capture: Off
```

### Compatibility

```text
Windows Version: Windows 11
Language: System
Dedicated Sandbox: Off
Use WineBridge: Off
DLL Overrides: 비움
```

### Advanced Display Settings

```text
Virtual Desktop: Off
Fullscreen Mouse Capture: Off
Take Focus: Off
Mouse Warp: Off
Window Manager Decorations: On
Screen Scaling: 100
Renderer: GL (Default)
```

설정 이유:

- **Virtual Desktop**: 일반 메신저에는 불필요
- **Fullscreen Mouse Capture**: 전체화면 게임용 기능
- **Take Focus**: 알림창이 포커스를 강제로 가져가는 것을 방지
- **Mouse Warp**: 게임용 상대 좌표 입력 기능
- **Window Manager Decorations**: KDE 제목 표시줄과 창 테두리 사용
- **Screen Scaling**: UI 크기에 문제가 없으면 100 유지
- **Renderer**: 일반 데스크톱 앱에는 GL 기본값 사용

## 받은 파일 폴더 연결

카카오톡 기본 다운로드 경로:

```text
C:\users\yonghun\Documents\KakaoTalkDownloads
```

Bottle 내부 실제 경로:

```text
~/.var/app/com.usebottles.bottles/data/bottles/bottles/kakaotalk/drive_c/users/yonghun/Documents/KakaoTalkDownloads
```

홈 디렉터리에 심볼릭 링크를 만듭니다.

```bash
ln -sT \
  "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/kakaotalk/drive_c/users/yonghun/Documents/KakaoTalkDownloads" \
  "$HOME/KakaoTalkDownloads"
```

확인:

```bash
ls -ld "$HOME/KakaoTalkDownloads"
```

`-T`는 기존 링크를 디렉터리처럼 따라 들어가 내부에 중복 링크가 생성되는 것을 방지합니다.

주의:

- 홈에는 링크만 있고 실제 파일은 Bottle 내부에 있습니다.
- Bottle을 삭제하면 원본 파일도 함께 삭제됩니다.
- 중요한 파일은 별도 위치에 복사합니다.

## 업데이트

### 카카오톡

카카오톡 자체 업데이터를 사용합니다. 자동 업데이트가 실패하면 최신 설치 파일을 같은 Bottle에서 다시 실행합니다.

```text
kakaotalk Bottle
→ Run Executable...
→ KakaoTalk_Setup.exe
```

### Bottles

자동 업데이트는 비활성화되어 있습니다.

```bash
flatpak update com.usebottles.bottles
```

## 직접 실행

Bottles의 프로그램 목록에서 카카오톡 바로가기를 생성하면 Bottles GUI를 열지 않고 실행할 수 있습니다.

Bottles 설정을 변경할 때는:

```bash
flatpak run com.usebottles.bottles
```

설정 위치:

| 설정 대상 | 설정 위치 |
|---|---|
| 알림, 채팅, 다운로드 폴더 | 카카오톡 내부 설정 |
| 렌더러, Wine 버전, 환경변수 | `kakaotalk` Bottle 설정 |
| Flatpak 파일 접근 권한 | Flatpak override 또는 Flatseal |
| 시스템 전체 화면 배율 | KDE 시스템 설정 |

## 현재 확인된 구성

```text
Bottles: Flatpak
Bottle: kakaotalk
Runner: sys-wine-11.0
Windows version: Windows 11
Renderer: GL
Wayland driver: Off
한글 입력: XMODIFIERS=@im=fcitx
다운로드 폴더: ~/KakaoTalkDownloads
```

---

## Repository scope

Included:

- NixOS host configurations
- Home Manager base user configuration
- Shared system tools
- Hardware and boot settings
- Locally packaged desktop applications
- Reproducible Flatpak declarations

Excluded:

- Project-specific Python and R environments
- Large datasets
- Private keys and credentials
- Wine Bottle data
- Nix build-result symlinks such as `result`

## Related repositories

- [dotfiles](https://github.com/YONGHUNI/dotfiles): shared shell, Vim, tmux, and R configuration for WSL and remote systems
