# Bottles와 카카오톡

LG Gram의 NixOS 환경에서 **Flatpak + Bottles + sys-wine**으로 Windows용 카카오톡을 실행한다.

## 구성 구조

```text
NixOS
├─ System Wine
└─ Flatpak
   └─ Bottles
      └─ kakaotalk Bottle
         └─ sys-wine
            └─ KakaoTalk.exe
```

각 요소의 역할:

- **Flatpak**: Bottles 애플리케이션을 설치하고 sandbox 안에서 실행
- **Bottles**: Windows 애플리케이션별 Wine prefix와 설정 관리
- **Bottle**: Bottles 내부의 독립된 Windows 실행 환경
- **System Wine**: NixOS에 설치된 Wine
- **sys-wine**: Bottle이 NixOS의 System Wine을 runner로 사용하는 방식

## 선언적 구성과 mutable data

### NixOS configuration으로 관리되는 항목

다음 항목은 Nix 설정에 선언되어 있다.

- Flatpak 서비스
- Flathub remote
- Bottles Flatpak
- System Wine

설정 위치:

```text
hosts/gram/configuration.nix
```

System Wine:

```nix
environment.systemPackages = with pkgs; [
  wineWow64Packages.stable
];
```

Bottles Flatpak:

```nix
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

### Bottles가 관리하는 mutable data

다음 항목은 Nix configuration으로 재현되지 않는다.

- `kakaotalk` Bottle 생성
- Bottle의 Wine prefix
- Bottle registry
- runner 선택
- Bottle 환경변수
- Windows version
- CJK font dependency
- 카카오톡 설치
- 카카오톡 내부 설정
- 채팅 기록과 다운로드 파일
- Bottles GUI에서 변경한 세부 설정

즉, Bottles 애플리케이션과 System Wine은 선언적으로 설치되지만, Bottle 내부 상태는 일반 애플리케이션 데이터로 관리된다.

## 적용

```bash
cd ~/nix-config
nix flake check
sudo nixos-rebuild switch --flake .#gram
```

System Wine 확인:

```bash
wine --version
```

현재 확인된 버전:

```text
wine-11.0
```

Bottles 설치 확인:

```bash
flatpak list --app | grep -i bottles
```

## Bottles 실행

```bash
flatpak run com.usebottles.bottles
```

KDE 메뉴에 Bottles가 즉시 나타나지 않으면 서비스 캐시를 다시 생성한다.

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

Bottles UI에서는 runner가 다음처럼 구체적인 버전으로 표시될 수 있다.

```text
sys-wine-11.0
```

## Soda runner 오류

Soda runner에서는 카카오톡 실행 시 다음 Themida 오류가 발생했다.

```text
An Error has occurred while loading imports. Wrong DLL present.
```

같은 Bottle에서 runner를 `sys-wine`으로 변경하면 실행된다.

현재 카카오톡 Bottle은 NixOS에 선언된 System Wine을 사용한다.

## 카카오톡 설치

1. 카카오 공식 사이트에서 Windows 64비트 설치 파일을 다운로드한다.
2. Bottles에서 `kakaotalk` Bottle을 연다.
3. `Run Executable...`을 선택한다.
4. `KakaoTalk_Setup.exe`를 실행한다.
5. 일반 Windows 설치 절차대로 설치한다.

`Install Programs...`는 Bottles의 커뮤니티 설치 목록을 사용하는 기능이다. 카카오톡 설치에는 `Run Executable...`을 사용한다.

설치가 끝나면 설치 파일은 삭제해도 된다.

```bash
rm ~/Downloads/KakaoTalk_Setup.exe
```

## 한글 폰트

한글이 `□□□`처럼 표시되면 Bottle에 CJK 글꼴을 설치한다.

```text
kakaotalk Bottle
→ Dependencies
→ cjkfonts
```

설치 후 카카오톡 설치 프로그램과 카카오톡을 완전히 종료한 뒤 다시 실행한다.

## 한글 입력

Bottle 환경변수에 다음 변수 하나를 추가한다.

```text
XMODIFIERS=@im=fcitx
```

설정 경로:

```text
kakaotalk Bottle
→ Settings
→ Environment Variables
```

현재 구성에서는 다음 변수를 추가하지 않는다.

```text
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
SDL_IM_MODULE=fcitx
FCITX_XIM_IBUS=1
```

특히 다음 변수를 추가하면 카카오톡에서 한글 입력이 다시 작동하지 않았다.

```text
FCITX_XIM_IBUS=1
```

## 파란 preedit 상자

한글 조합 중 파란 preedit 상자가 나타난다.

이는 Wine이 Fcitx5의 XIM 입력을 처리하는 방식에서 발생한다.

현재 동작:

- `XMODIFIERS=@im=fcitx`만 유지하면 한글 입력은 정상 동작
- Wine의 실험적 Wayland driver에서는 inline 조합이 가능
- Wayland driver 사용 시 작은 보조 창이 나타나는 문제가 있었음
- 안정성을 위해 기본 XWayland/XIM 방식을 사용

## 권장 Bottle 설정

### Components

```text
Runner: sys-wine-11.0
DXVK: Disabled
VKD3D: Disabled
LatencyFleX: Disabled
```

카카오톡은 일반 데스크톱 애플리케이션이므로 DirectX translation layer가 필요하지 않다.

### Display

```text
Discrete Graphics: Off
Wayland (Experimental): Off
Post-Processing Effects: Off
Gamescope: Off
```

- **Discrete Graphics**: 카카오톡 실행에 고성능 GPU가 필요하지 않음
- **Wayland (Experimental)**: 보조 창과 입력 문제가 있어 비활성화
- **Post-Processing Effects**: 게임용 후처리 기능
- **Gamescope**: 게임용 compositor

### Performance

```text
Synchronization: System
Monitor Performance: Off
Feral GameMode: Off
Preload Game Files: Off
OBS Game Capture: Off
```

카카오톡에는 게임 최적화 기능이 필요하지 않다.

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
- **Mouse Warp**: 게임용 상대 좌표 입력
- **Window Manager Decorations**: KDE 제목 표시줄과 창 테두리 사용
- **Screen Scaling**: UI 크기에 문제가 없으면 100 유지
- **Renderer**: 일반 데스크톱 애플리케이션에는 GL 기본값 사용

## 받은 파일 폴더 연결

카카오톡 기본 다운로드 경로:

```text
C:\users\yonghun\Documents\KakaoTalkDownloads
```

Bottle 내부 실제 경로:

```text
~/.var/app/com.usebottles.bottles/data/bottles/bottles/kakaotalk/drive_c/users/yonghun/Documents/KakaoTalkDownloads
```

홈 디렉터리에 심볼릭 링크를 만든다.

```bash
ln -sT \
  "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/kakaotalk/drive_c/users/yonghun/Documents/KakaoTalkDownloads" \
  "$HOME/KakaoTalkDownloads"
```

확인:

```bash
ls -ld "$HOME/KakaoTalkDownloads"
```

`-T`는 기존 링크를 디렉터리처럼 따라 들어가 링크 내부에 중복 링크가 생성되는 것을 방지한다.

주의:

- 홈 디렉터리에는 심볼릭 링크만 존재한다.
- 실제 파일은 Bottle 내부에 있다.
- Bottle을 삭제하면 원본 파일도 함께 삭제될 수 있다.
- 중요한 파일은 별도 위치에 복사하거나 백업한다.

## 업데이트

### Bottles

Bottles Flatpak 자동 업데이트는 비활성화되어 있다.

수동 업데이트:

```bash
flatpak update com.usebottles.bottles
```

### 카카오톡

카카오톡 자체 updater를 사용한다.

자동 업데이트가 실패하면 최신 설치 파일을 같은 Bottle에서 다시 실행한다.

```text
kakaotalk Bottle
→ Run Executable...
→ KakaoTalk_Setup.exe
```

### System Wine

System Wine은 NixOS configuration의 다음 패키지로 관리한다.

```nix
wineWow64Packages.stable
```

Wine 버전은 고정된 nixpkgs input에 따라 결정된다.

업데이트 후 확인:

```bash
wine --version
```

## 직접 실행

Bottles의 프로그램 목록에서 카카오톡 바로가기를 생성하면 Bottles GUI를 먼저 열지 않고 실행할 수 있다.

Bottles 설정을 변경할 때는 다음 명령으로 GUI를 연다.

```bash
flatpak run com.usebottles.bottles
```

## 설정 위치 구분

| 설정 대상 | 설정 위치 |
|---|---|
| 알림, 채팅, 다운로드 폴더 | 카카오톡 내부 설정 |
| Wine runner, 렌더러, 환경변수 | `kakaotalk` Bottle 설정 |
| Bottles 설치와 System Wine | NixOS configuration |
| Flatpak 파일 접근 권한 | Flatpak override 또는 Flatseal |
| 시스템 전체 화면 배율 | KDE 시스템 설정 |

## 백업과 복구

NixOS configuration만으로는 Bottle 내부 상태와 카카오톡 설치를 복구할 수 없다.

Bottle data 경로:

```text
~/.var/app/com.usebottles.bottles/data/bottles/
```

백업이 필요한 항목:

- `kakaotalk` Bottle
- 카카오톡 다운로드 파일
- 필요한 경우 Bottle registry와 설정
- 카카오톡에서 별도로 보존해야 하는 사용자 데이터

Bottle을 삭제하기 전에 다운로드 파일과 필요한 데이터를 별도 위치에 복사한다.

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

[← README로 돌아가기](../README.md)
