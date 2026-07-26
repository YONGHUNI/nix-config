# HOP 패키징 및 실행

[HOP](https://github.com/golbin/hop)은 HWP와 HWPX 문서를 열고 편집할 수 있는 오픈소스 데스크톱 프로그램이다.

이 저장소에서는 HOP의 공식 Linux `.deb` 패키지를 Nix 패키지로 재포장한다.

## 관리 방식

HOP는 다음 두 파일을 통해 선언적으로 설치된다.

```text
pkgs/hop/default.nix
home/yonghun.nix
```

`pkgs/hop/default.nix`은 다음을 정의한다.

- 고정된 HOP 버전
- 공식 `.deb` 다운로드 URL
- 고정된 SRI hash
- 실행에 필요한 라이브러리
- NixOS용 ELF patching
- GTK 및 GSettings wrapper
- GStreamer plugin 경로
- XWayland 및 WebKitGTK 우회 설정
- desktop entry

`home/yonghun.nix`에서는 패키지를 불러와 `home.packages`에 포함한다.

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

따라서 HOP 설치와 제거는 Home Manager가 포함된 NixOS generation을 통해 관리된다.

## 적용

```bash
cd ~/nix-config

nix flake check
sudo nixos-rebuild build --flake .#gram
sudo nixos-rebuild switch --flake .#gram
```

## 실행

기본 실행 파일:

```bash
hop-desktop
```

편의를 위한 별칭도 제공한다.

```bash
hop
```

desktop entry가 정상적으로 설치되면 KDE 애플리케이션 메뉴에서도 HOP을 실행할 수 있다.

메뉴에 즉시 나타나지 않으면 KDE 서비스 캐시를 다시 생성한다.

```bash
kbuildsycoca6
```

## 패키지 구성

설정 위치:

```text
pkgs/hop/default.nix
```

### 버전과 소스

HOP 버전과 `.deb` 파일의 hash를 고정한다.

```nix
pname = "hop";
version = "0.4.1";

src = fetchurl {
  url = "https://github.com/golbin/hop/releases/download/v${version}/HOP-linux-x64.deb";
  hash = "sha256-p4wOSzwBXI/2NRTZTIqh/ZGvnTufK554CJVl5cfYHQg=";
};
```

### 빌드 도구

```nix
nativeBuildInputs = [
  dpkg
  autoPatchelfHook
  wrapGAppsHook3
];
```

각 도구의 역할:

- `dpkg`: 공식 `.deb` 파일 압축 해제
- `autoPatchelfHook`: NixOS에서 필요한 ELF interpreter와 library 경로 연결
- `wrapGAppsHook3`: GTK, GSettings, dconf, GIO 및 GdkPixbuf 환경 구성

### 런타임 라이브러리

주요 라이브러리:

```nix
buildInputs = [
  glib
  gtk3
  webkitgtk_4_1
  libsoup_3
  openssl
  cairo
  pango
  gdk-pixbuf
  atk
  dbus
  libayatana-appindicator

  gst_all_1.gstreamer
  gst_all_1.gst-plugins-base
];
```

### `.deb` 압축 해제

```nix
unpackPhase = ''
  runHook preUnpack
  dpkg-deb -x "$src" .
  runHook postUnpack
'';
```

### 설치

```nix
installPhase = ''
  runHook preInstall

  mkdir -p "$out"
  cp -r usr/* "$out/"

  if [ -d opt ]; then
    mkdir -p "$out/opt"
    cp -r opt/* "$out/opt/"
  fi

  ln -s "$out/bin/hop-desktop" "$out/bin/hop"

  install -Dm644 \
    "${desktopItem}/share/applications/hop.desktop" \
    "$out/share/applications/hop.desktop"

  runHook postInstall
'';
```

## NixOS 런타임 처리

HOP은 Tauri와 WebKitGTK를 사용한다.

공식 `.deb`를 단순히 압축 해제하는 것만으로는 NixOS에서 정상 실행되지 않았고, 다음 문제를 별도로 처리해야 했다.

## GStreamer `appsink`

초기 실행 시 다음 메시지가 나타났다.

```text
GStreamer element appsink not found. Please install it.
```

`appsink`는 `gst-plugins-base`의 `libgstapp.so`에 포함된다.

HOP wrapper에서 다음 경로를 `GST_PLUGIN_SYSTEM_PATH_1_0`에 추가한다.

```text
${gst_all_1.gst-plugins-base}/lib/gstreamer-1.0
```

관련 설정:

```nix
gappsWrapperArgs+=(
  --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gst_all_1.gst-plugins-base}/lib/gstreamer-1.0"
)
```

## Wayland 렌더링 문제

KDE Wayland에서 HOP을 기본 설정으로 실행하면 UI가 화면 왼쪽의 매우 좁은 영역으로 압축되어 표시되는 문제가 있었다.

현재는 HOP만 XWayland로 실행하고 WebKitGTK의 일부 렌더링 기능을 비활성화한다.

```text
GDK_BACKEND=x11
WEBKIT_DISABLE_DMABUF_RENDERER=1
WEBKIT_DISABLE_COMPOSITING_MODE=1
```

관련 설정:

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

이 변수들은 HOP wrapper에 포함되어 있으므로 일반 실행 시 직접 지정하지 않아도 된다.

## GTK 파일 선택기 충돌

파일 열기 또는 다른 이름으로 저장을 실행할 때 GTK 파일 선택기가 나타나기 직전에 HOP이 `SIGABRT`로 종료되는 문제가 있었다.

원인은 GTK 파일 선택기가 사용하는 다음 런타임 요소가 노출되지 않았기 때문이다.

- GTK3 GSettings schema
- `gsettings-desktop-schemas`
- dconf GIO backend
- GdkPixbuf loader

이를 해결하기 위해 `makeWrapper`만 사용하는 대신 `wrapGAppsHook3`를 적용한다.

정상 적용되면 로그에서 다음과 같은 메시지를 확인할 수 있다.

```text
Found default implementation dconf for ‘gsettings-backend’
watch_fast: "/org/gtk/settings/file-chooser/"
```

## 업데이트

새 HOP 버전이 공개되면 `pkgs/hop/default.nix`의 `version`과 `src.hash`를 갱신한다.

### 1. 새 버전 확인

예:

```nix
version = "NEW_VERSION";
```

### 2. 새 파일의 hash 계산

```bash
nix store prefetch-file \
  "https://github.com/golbin/hop/releases/download/vNEW_VERSION/HOP-linux-x64.deb"
```

출력된 SRI hash를 다음 위치에 반영한다.

```nix
src = fetchurl {
  url = "https://github.com/golbin/hop/releases/download/v${version}/HOP-linux-x64.deb";
  hash = "sha256-...";
};
```

### 3. 검증

```bash
cd ~/nix-config
nix flake check
sudo nixos-rebuild build --flake .#gram
```

### 4. 적용 및 실행 확인

```bash
sudo nixos-rebuild switch --flake .#gram
hop-desktop
```

확인할 기능:

- 애플리케이션 실행
- HWP/HWPX 파일 열기
- 파일 선택기
- 다른 이름으로 저장
- 한글 입력
- KDE 메뉴의 desktop entry
- Wayland 세션에서 창 크기와 렌더링

## 문제 해결

### `appsink` 오류

```text
GStreamer element appsink not found
```

`GST_PLUGIN_SYSTEM_PATH_1_0`에 `gst-plugins-base` 경로가 포함되었는지 확인한다.

### UI가 좁은 영역에 압축되는 경우

다음 변수가 wrapper에 적용되었는지 확인한다.

```text
GDK_BACKEND=x11
WEBKIT_DISABLE_DMABUF_RENDERER=1
WEBKIT_DISABLE_COMPOSITING_MODE=1
```

### 파일 선택기에서 종료되는 경우

`wrapGAppsHook3`가 `nativeBuildInputs`에 포함되었는지 확인한다.

```nix
nativeBuildInputs = [
  dpkg
  autoPatchelfHook
  wrapGAppsHook3
];
```

### KDE 메뉴에 나타나지 않는 경우

```bash
kbuildsycoca6
```

desktop entry 확인:

```bash
ls ~/.nix-profile/share/applications/ | grep hop
```

### 현재 실행 파일 확인

```bash
command -v hop
command -v hop-desktop
```

---

[← README로 돌아가기](../README.md)
