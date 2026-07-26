# LG Gram 터치패드 Fn+F5 및 상태 LED

LG Gram에서 `Fn+F5`를 누르면 터치패드가 잠시 비활성화된 뒤 바로 다시 활성화되는 문제가 있었다.

## 원인

입력 이벤트가 두 번 처리되는 것이 원인이었다.

1. LG 펌웨어가 터치패드 상태를 전환한다.
2. `lg_laptop` 커널 모듈이 같은 키를 `KEY_F21` 이벤트로 전달한다.
3. KDE Plasma가 `KEY_F21`을 다시 처리하면서 터치패드 상태를 한 번 더 전환한다.

결과적으로 터치패드가 꺼진 직후 다시 켜지거나, 켜진 직후 다시 꺼질 수 있다.

## `lg_laptop` 모듈을 유지하는 이유

`lg_laptop` 모듈을 비활성화하면 중복 입력 문제는 사라지지만, 다음 LG 전용 기능도 사용할 수 없게 된다.

- 배터리 충전 제한
- 키보드 백라이트
- 터치패드 LED
- 팬 모드
- 리더 모드
- Fn Lock
- USB 충전 설정

따라서 `lg_laptop` 모듈은 유지하고, KDE가 별도로 처리하지 않는 키로 `Fn+F5` 이벤트를 재매핑한다.

현재는 `KEY_F21`을 `F24`로 재매핑한다.

## 시스템 설정

설정 위치:

```text
hosts/gram/configuration.nix
```

### 키 이벤트 재매핑

```nix
# Remap the LG Fn+F5 hotkey from KEY_F21 to F24.
services.udev.extraHwdb = ''
  evdev:name:LG WMI hotkeys:*
   KEYBOARD_KEY_74=f24
'';
```

이 설정은 `LG WMI hotkeys` 장치가 전달하는 해당 scan code를 `F24`로 변경한다.

LG 펌웨어가 수행하는 터치패드 상태 전환은 그대로 유지되지만, KDE가 기본 터치패드 토글 키로 다시 처리하지는 않는다.

### 터치패드 LED 쓰기 권한

```nix
# Allow members of the users group to control the touchpad LED.
services.udev.extraRules = ''
  ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpad_led", RUN+="${pkgs.coreutils}/bin/chgrp users /sys%p/brightness"
  ACTION=="add", SUBSYSTEM=="leds", KERNEL=="tpad_led", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/brightness"
'';
```

터치패드 LED는 다음 인터페이스를 통해 제어한다.

```text
/sys/class/leds/tpad_led/brightness
```

일반 사용자 세션에서 LED를 동기화할 수 있도록 `users` 그룹에 쓰기 권한을 부여한다.

## 사용자 설정

설정 위치:

```text
hosts/gram/home.nix
```

Plasma에서 `F24`를 전역 단축키로 등록한다.

```nix
hotkeys.commands."sync-touchpad-led" = {
  name = "Sync touchpad LED";
  key = "F24";
  command = "${syncTouchpadLed}/bin/sync-touchpad-led";
};
```

`Fn+F5`를 누르면 다음 순서로 동작한다.

1. LG 펌웨어가 터치패드 상태를 변경한다.
2. 재매핑된 `F24` 이벤트가 Plasma에 전달된다.
3. `sync-touchpad-led` 스크립트가 실행된다.
4. KWin이 보고하는 실제 터치패드 상태를 읽는다.
5. 실제 상태에 맞춰 터치패드 LED를 갱신한다.

## 터치패드 장치 탐색

입력 장치의 `event` 번호는 부팅이나 장치 구성에 따라 바뀔 수 있다.

예를 들어 현재 터치패드가 `event8`이어도 다음 부팅에서는 다른 번호가 될 수 있다.

따라서 스크립트는 다음 경로에서 장치 목록을 가져온다.

```text
/org/kde/KWin/InputDevice
```

KWin의 `devicesSysNames` 목록을 순회한 뒤, 다음 property가 참인 장치를 터치패드로 선택한다.

```text
touchpad = true
```

특정 `event` 번호는 하드코딩하지 않는다.

## 상태와 LED 매핑

KWin이 보고하는 터치패드 상태와 LED 값은 다음과 같이 대응한다.

```text
b true  → 1
b false → 0
```

현재 설정에서는:

- 터치패드 활성화: LED 켜짐
- 터치패드 비활성화: LED 꺼짐

으로 동작한다.

## 확인

### KWin이 보고하는 터치패드 상태

아래의 `event8`은 예시다. 실제 장치 번호는 다를 수 있다.

```bash
busctl --user get-property \
  org.kde.KWin \
  /org/kde/KWin/InputDevice/event8 \
  org.kde.KWin.InputDevice \
  enabled
```

가능한 결과:

```text
b true
```

또는:

```text
b false
```

### LED 상태

```bash
cat /sys/class/leds/tpad_led/brightness
```

가능한 결과:

```text
1
```

또는:

```text
0
```

### KWin 입력 장치 목록

```bash
busctl --user get-property \
  org.kde.KWin \
  /org/kde/KWin/InputDevice \
  org.kde.KWin.InputDeviceManager \
  devicesSysNames
```

## 적용

```bash
cd ~/nix-config
nix flake check
sudo nixos-rebuild switch --flake .#gram
```

HWDB와 udev 규칙이 즉시 완전히 반영되지 않으면 재부팅한다.

## 문제 해결

### 터치패드 LED 인터페이스가 없는 경우

확인:

```bash
ls -l /sys/class/leds/
```

다음 항목이 있어야 한다.

```text
tpad_led
```

없다면 `lg_laptop` 모듈이 로드되었는지 확인한다.

```bash
lsmod | grep lg_laptop
```

### LED 파일에 쓸 수 없는 경우

```bash
ls -l /sys/class/leds/tpad_led/brightness
```

현재 사용자가 `users` 그룹에 포함되어 있는지도 확인한다.

```bash
groups
```

### KWin에서 터치패드를 찾지 못하는 경우

KWin이 제공하는 입력 장치 목록을 확인한다.

```bash
busctl --user tree org.kde.KWin /org/kde/KWin/InputDevice
```

각 장치의 `touchpad` property를 확인한다.

```bash
busctl --user get-property \
  org.kde.KWin \
  /org/kde/KWin/InputDevice/eventN \
  org.kde.KWin.InputDevice \
  touchpad
```

`eventN`은 실제 장치 이름으로 바꾼다.

### 키 이벤트 확인

필요하면 `wev`를 실행하고 `Fn+F5`를 눌러 `F24` 이벤트가 전달되는지 확인한다.

```bash
wev
```

---

[← README로 돌아가기](../README.md)
