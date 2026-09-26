# iMac-setup.sh 설계 기록

대상: macOS Sequoia 15.7 (x86_64 iMac 포함) + 구름 입력기 1.13.2.
관리자가 `/Library/Input Methods/Gureum.app` 과 로그인 에이전트 `kr.codyssey.gureum.init`
(`/usr/local/bin/init_gureum.sh` → `open -g Gureum.app` 후 `set_gureum_ime.swift` 로 Apple 두벌식 비활성화,
구름 두벌식 `TISEnableInputSource` + `TISSelectInputSource`)을 설치해 둔 환경이다.

## 설정이 저장되는 곳

| 항목 | 도메인 / 키 | 비고 |
|---|---|---|
| fn 키 동작 | `com.apple.HIToolbox` `AppleFnUsageType` | 1 = 입력 소스 변경 |
| Caps Lock → fn | ByHost `.GlobalPreferences` `com.apple.keyboard.modifiermapping.<VID>-<PID>-<CC>` | 정수 값. 즉시 적용은 HID 이벤트 시스템에 `HIDKeyboardModifierMappingPairs` 를 직접 넣는다 |
| Apple 입력 소스 | `com.apple.HIToolbox` `AppleEnabledInputSources` | |
| 서드파티 입력 소스 | `com.apple.inputsources` `AppleEnabledThirdPartyInputSources` | 구름은 여기. `Keyboard Input Method` 항목 하나 + 배열마다 `Input Mode` 항목 |

System Settings 에서 구름 세벌식 최종을 켠 정상 상태의 실제 내용:

```
AppleEnabledThirdPartyInputSources = (
  { "Bundle ID" = "org.youknowone.inputmethod.Gureum"; InputSourceKind = "Keyboard Input Method"; },
  { "Bundle ID" = "org.youknowone.inputmethod.Gureum"; "Input Mode" = "org.youknowone.inputmethod.Gureum.han3final"; InputSourceKind = "Input Mode"; }
)
```

이때 `com.apple.HIToolbox` `AppleEnabledInputSources` 에는 구름 항목이 없다. 예전 버전이 여기에 구름을 넣어
설정 화면에 같은 항목이 여러 개 보였다.

## 이력

- 1차(473965b): HIToolbox `AppleEnabledInputSources` 에 구름 `Input Mode` 항목을 PlistBuddy 로 추가. 설정 화면 중복.
- 2차(5dad035): `TISEnableInputSource` 로 켜고 HIToolbox 에도 저장. 서드파티 승인 확인 창이 뜸.
- 3차(9457216): `com.apple.inputsources` 에 저장 + 배포 알림 + TextInputMenuAgent 재시작. 목록에는 보이지만 선택이 안 됨(아래).
- 4차(2026-09-21): 저장은 3차와 같고, 전파를 TIS API(`TISDisableInputSource`)로 바꿈. 아래 조사 결과에 따른 것.
- 5차(2026-09-21): 실습 iMac 에서 4차가 실패. 덤 배열을 구름 로마자(`system`)로 바꾸고, 요청하지 않았는데
  켜져 있는 구름 배열이 없어질 때까지 끄기를 되풀이하도록 바꿈. 아래 2차 조사 참고.

## 2026-09-21 조사: 목록에는 보이는데 동작하지 않는 문제

### 증상 (사용자 보고)

- 스크립트 실행 후 System Settings 를 닫았다 열면 설정이 모두 등록된 것으로 보인다.
- 메뉴 막대 입력 메뉴에 구름이 보이지만 골라도 입력이 안 되고 아이콘도 바뀌지 않는다.
- 설정에서 모두 지우고 다시 추가하려 하면 구름 세벌식이 회색(이미 추가됨)으로 나온다.
  내장 세벌식을 추가했다 지우면 그때부터 구름 세벌식이 목록에 나타나고 동작한다.

### 확인한 사실

1. 새 프로세스에서 `TISCreateInputSourceList` + `kTISPropertyInputSourceIsEnabled` 로 보면 스크립트가 저장한 구름 배열은
   "켜짐"이다. 저장 위치와 형식은 문제가 없다. (`--list`, `han3final` 실행 뒤 확인)
2. 런루프를 돌리는 장수 프로세스(JXA, `NSRunLoop.runUntilDate`)를 먼저 띄워 두고 파일을 고치면, 그 프로세스는 끝까지 예전
   상태를 보고한다. 다음을 모두 시도했지만 갱신되지 않았다.
   - `defaults import com.apple.inputsources`
   - 배포 알림 `AppleEnabledInputSourcesChangedNotification`, `com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged`
   - Darwin 알림(`notifyutil -p`) `com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged`,
     `TISNotifyEnabledKeyboardInputSourcesChanged`, `com.apple.Carbon.TISNotifyInstalledInputSourcesChanged`
   - 배포 알림 `AppleInstalledInputSourcesChangedNotification`
   - `launchctl kickstart -k gui/<uid>/com.apple.TextInputMenuAgent` (메뉴 막대만 다시 뜬다. 앱은 그대로)
3. 같은 장수 프로세스가 **TIS API 호출은 즉시 반영**한다. Apple 자판(Dvorak)을 `TISEnableInputSource` / `TISDisableInputSource`
   로 켜고 끄면 1초 안에 상태가 바뀐다. 즉 System Settings 가 하는 것과 같은 API 호출만이 실행 중인 모든 프로세스에 전파된다.
4. `TISEnableInputSource` 를 osascript 에서 구름 배열에 대해 부르면 반환값은 0 이지만 저장도 전파도 되지 않는다(서드파티 승인
   게이트). 확인 창은 이번에는 뜨지 않았다(2차 때는 떴다고 기록됨).
5. `TISDisableInputSource` 는 구름 배열에 대해 정상 동작하고, 그 순간 장수 프로세스가 목록 전체를 다시 읽어 방금 파일로 추가한
   다른 구름 배열까지 "켜짐"으로 바뀐다.
6. 참고: JXA 의 `delay()` 는 런루프를 돌리지 않아 알림을 받지 못한다. 감시 프로세스는 `NSRunLoop` 를 써야 한다.
   또 zsh 에서 `log` 는 내장 명령이라 `/usr/bin/log show` 로 불러야 하고, 전체 디스크 접근 권한이 없는 터미널에서는 로그
   저장소를 열 수 없다.

### 해석

메뉴 막대에서 구름을 고르면 TextInputMenuAgent 가 선택을 요청하지만, 앞에 떠 있는 앱은 자기 캐시에 구름이 "켜지지 않은 소스"
이므로 무시한다. 그래서 아이콘도 바뀌지 않는다. System Settings 에서 아무 입력 소스나 추가했다 지우면 API 호출이 일어나
모든 프로세스가 목록을 다시 읽고, 그때부터 동작한다. 사용자가 "내장 세벌식을 추가했다 지우니 동작했다"고 한 것이 정확히 이것이다.

### 적용한 해결

1. `com.apple.inputsources` 에 구름 IM 항목 + 두벌식 + 요청 배열을 쓰면서, **쓰지 않는 구름 배열 하나를 덤으로 추가**한다
   (`gureum_modes` 결과 중 요청 목록에 없는 첫 번째, 보통 `colemak`).
2. 곧바로 덤 배열을 `TISDisableInputSource` 로 끈다(`DISABLE_JS`). 이 호출이 목록 변경을 모든 프로세스에 전파하고, 덤 배열은
   저장에서도 사라진다.
3. 설정을 바꾸기 전에 감시 프로세스(`WATCH_JS`)를 띄워 두고, 끝날 때 그 프로세스가 요청 배열을 모두 "켜짐"으로 보는지 확인한다.
   새 프로세스 확인(`TIS_JS`)은 저장 파일만 보여 주므로 전파 여부는 이것으로만 알 수 있다.
4. 배포 알림 전송과 TextInputMenuAgent 재시작은 제거했다.

### 검증 (2026-09-21, 이 Mac)

- 파일만 고쳐 han2 를 뺀 뒤(전파 없음) 외부 감시 프로세스를 띄우고 `sh iMac-setup.sh han3final` 실행.
- 외부 감시 프로세스가 약 2초 안에 "켜짐"으로 바뀜. 스크립트 출력 마지막 줄 `실행 중인 앱과 메뉴 막대에도 반영됨`.
- 끝 상태: `com.apple.inputsources` 에 구름 IM + han2 + han3final 만 있음(덤 배열 없음), HIToolbox 에 구름 항목 없음,
  남은 osascript 프로세스 없음. 실행 시간 약 1.8초. 확인 창 없음.

## 2026-09-21 2차 조사: 실습 iMac 에서 구름 로마자가 남고 전파가 안 되는 문제

### 증상 (사용자 보고, 실습 iMac)

- 메뉴 막대에 로마자 아이콘이 나타났다가 입력 모드에 들어가면 사라진다.
- 입력란 아래 입력 소스 전환 메뉴에 구름이 보이지 않고 ABC 의 `A` 만 있다 (= 실행 중인 앱에 전파 안 됨).
- System Settings 목록: ABC, **구름 로마자**, 구름 두벌식. 구름 로마자는 스크립트가 쓴 적이 없다.
- 구름 로마자와 구름 두벌식을 지우고 구름 두벌식만 다시 추가하면 정상 동작한다.

### 확인한 사실

1. `Gureum.app/Contents/Info.plist` 의 `ComponentInputModeDict:tsInputModeListKey` 에서
   `tsInputModeDefaultStateKey` 가 참인 배열은 **`han2`(두벌식)와 `system`(로마자) 둘뿐**이다.
   로그인 에이전트가 `TISEnableInputSource` 로 구름 입력기를 켜면 macOS 가 이 둘을 자동으로 켠다.
   실습 iMac 의 목록 `ABC + 구름 로마자 + 구름 두벌식` 이 정확히 이 상태다.
2. `system` 은 `tsInputModeScriptKey = smRoman`, `tsInputModePrimaryInScriptKey = true` 다. 켜져 있으면
   로마자 자리를 ABC 대신 차지해 메뉴 막대에 "로마자"가 뜨고 앱의 입력 소스 전환이 어긋난다.
   (`ko.lproj/InfoPlist.strings`: `system` = "로마자", `hanroman` = "한글 로마자",
   `colemak`/`dvorak`/`qwerty` = "… (제거예정)")
3. **이미 꺼져 있는 입력 소스에 `TISDisableInputSource` 를 부르면 아무 일도 일어나지 않는다.**
   반환값은 `noErr`(0)이지만 상태 변화가 없으니 전파도 없다. 미리 띄워 둔 감시 프로세스가 10초 내내
   `pending` 이었다. 4차의 덤 배열(`colemak`)은 목록 파일에 함께 써 두므로 보통은 "켜진" 것으로 읽혀
   동작했지만, 이 조건이 깨지면 전파와 목록 정리가 둘 다 조용히 실패한다.
4. `TISCreateInputSourceList(filter, false)` 로 `kTISPropertyBundleID` 를 걸면 지금 켜져 있는 구름 배열
   전부를 한 번의 osascript 호출(약 0.1초)로 얻을 수 있다.
5. `defaults import` 직후 `plutil -p ~/Library/Preferences/com.apple.inputsources.plist` 로 보면 방금 지운
   항목이 남아 있는 것처럼 보인다. cfprefsd 가 아직 디스크에 내리지 않은 것뿐이다. 실제 값은
   `defaults export com.apple.inputsources -` 로 봐야 한다.

### 적용한 해결 (5차)

1. 덤 배열을 **구름 로마자(`system`)** 로 먼저 고른다(요청 목록에 없을 때). 어차피 꺼야 하는 배열이고,
   목록 파일에 켜서 쓴 뒤 끄므로 "켜진 것을 끈다"는 전파 조건도 만족한다. `system` 이 요청되었거나
   없으면 예전처럼 쓰지 않는 배열 아무거나 고른다.
2. 끄기를 한 번이 아니라 **요청하지 않았는데 켜져 있는 구름 배열이 하나도 없을 때까지** 되풀이한다
   (최대 4회). 로그인 에이전트나 macOS 가 자동으로 켠 배열까지 함께 정리된다.
3. 켜진 배열 목록은 `ENABLED_JS` 로 한 번에 읽는다(`stray_modes`).

### 검증 (2026-09-21, 개발용 Mac 에서 실습 iMac 상태를 재현)

- 목록을 `구름 IM + han2 + system` 으로 만들고 전파까지 시켜 실습 iMac 과 같은 상태를 만든 뒤
  미리 감시 프로세스를 띄우고 `sh iMac-setup.sh` 실행.
- 감시 프로세스가 본 구름 로마자: `enabled` → 약 3초 뒤 `disabled`. 스크립트 출력에
  `요청하지 않은 배열 system 끔`, 마지막 줄 `실행 중인 앱과 메뉴 막대에도 반영됨`.
- 끝 상태: `구름 IM + han2` 만. `sh iMac-setup.sh han3final` 도 같은 결과(`구름 IM + han2 + han3final`),
  실행 시간 1.9초, HIToolbox 에 구름 항목 없음, 남은 osascript 프로세스 없음.

## 2026-09-23 조사: 이더넷 iMac 과 와이파이 노트북을 서로 조작하는 방법

실습실 iMac 은 이더넷, 개인 노트북은 와이파이에 붙어 있다. iMac 은 일반 사용자 계정(관리자 아님),
노트북은 내 관리자 계정이다. 이 차이가 방향마다 쓸 수 있는 방법을 가른다.

### 먼저 확인: 두 망이 서로 통하는가

유선망과 와이파이가 다른 VLAN 이거나 클라이언트 격리가 걸려 있으면 IP 기반 방법은 전부 막힌다.

```sh
ipconfig getifaddr en0        # iMac: 이더넷 주소 (와이파이는 en1)
ping -c 3 <iMac 주소>          # 노트북에서
```

막혀 있으면 iMac 의 와이파이도 노트북과 같은 SSID 에 붙인다. 와이파이 접속은 일반 사용자도 할 수 있고,
서비스 순서상 이더넷이 앞이라 인터넷은 그대로 유선을 쓴다. 같은 와이파이 서브넷이면 Bonjour 탐색도 된다.
Bonjour 는 라우터를 넘지 못하므로 서브넷이 다르면 `vnc://주소` 처럼 IP 를 직접 적어야 한다.

### 방법별 정리

| 방법 | iMac 관리자 | 방향 | 조건 |
|---|---|---|---|
| 유니버설 컨트롤 | 불필요 | 양방향(키보드·마우스 공유) | 같은 Apple 계정(2단계 인증), 양쪽 와이파이·블루투스·Handoff 켬, 10 m 이내, 인터넷 공유 중이 아닐 것 |
| 노트북에 화면 공유·원격 로그인 켜기 | 불필요(노트북만 설정) | iMac → 노트북 | iMac 에서 `open vnc://노트북IP`, `ssh` |
| iMac 에 화면 공유·원격 로그인 켜기 | **필요** | 노트북 → iMac | 시스템 설정 > 일반 > 공유는 관리자 잠금 |
| Deskflow / RustDesk / AnyDesk | 설치는 불필요, 권한은 사실상 필요 | 양방향 | 접근성·화면 기록·입력 모니터링(TCC). Big Sur 이후 일반 사용자는 PPPC 프로파일 없이는 관리자 인증 없이 못 켬 |

- 유니버설 컨트롤은 이더넷 Mac 이라도 와이파이 라디오만 켜져 있으면 된다. Apple 문서는 인터넷 공유 중이
  아닐 것만 조건으로 두고 이더넷 사용은 제한하지 않는다. 와이파이를 끄면 Handoff 는 되어도 키보드·마우스는
  안 넘어간다는 보고가 있다. 실습이 끝나면 iMac 에서 Apple 계정을 로그아웃한다.
- Deskflow 계열은 앱을 `~/Applications` 에 두고 실행하는 것까지는 관리자 없이 된다. 문제는 접근성 권한이다.
  시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 스위치를 켤 때 관리자 암호를 요구하면 못 쓴다.
  화면 기록은 Monterey 12.3 부터 PPPC 프로파일 없이는 일반 사용자가 켤 수 없다(Jamf 커뮤니티 보고).
  접근성도 같은 방식으로 실습 iMac 에서 직접 확인해야 한다. Deskflow 는 서명이 없어 `xattr -d com.apple.quarantine`
  가 필요하고, 접근성 목록에 `Deskflow` 와 `deskflow` 를 둘 다 넣어야 한다.
- Sequoia 15.0 은 방화벽 문제로 Deskflow 가 안 됐지만 15.1 에서 고쳐졌다. 실습 iMac 은 15.7 이라 해당 없다.

### 권장 순서

1. 노트북에서 화면 공유와 원격 로그인을 켠다. iMac → 노트북 방향은 이것으로 끝난다.
2. iMac 에 Apple 계정으로 로그인하고 유니버설 컨트롤을 켠다. 시스템 설정 > 디스플레이 > 고급 >
   "근처의 Mac 이나 iPad 로 포인터와 키보드 이동 허용".
3. 화면 자체가 필요하면 iMac 접근성 권한을 일반 사용자가 켤 수 있는지 시험하고, 안 되면 관리자에게 화면 공유
   또는 PPPC 프로파일을 요청한다. 관리자는 이미 로그인 에이전트를 배포하고 있으니 프로파일 추가는 어렵지 않다.

### 검증

```sh
sudo systemsetup -setremotelogin on   # 노트북. 화면 공유는 시스템 설정 > 일반 > 공유에서 켠다
ssh <노트북사용자>@<노트북IP>            # iMac 에서
open vnc://<노트북IP>                  # iMac 에서
ipconfig getifaddr en1                # iMac 와이파이가 켜졌는지 (유니버설 컨트롤 전제)
```

### 실측 (2026-09-23, 노트북에서)

| 기기 | 주소 |
|---|---|
| 노트북 와이파이 | 10.19.224.214 (마스크 255.255.0.0, 게이트웨이 10.19.254.254) |
| iMac 이더넷 | 10.14.2.3 |
| iMac 와이파이 | 10.19.233.251 |

- 이더넷 주소 10.14.2.3 은 와이파이망에서 닿지 않는다(ping 무응답, 22·5900 모두 닫힘). 유선망과 와이파이망은
  서로 라우팅되지 않는다고 봐야 한다. **iMac 의 와이파이를 켜는 우회가 필수다.**
- 와이파이망은 /16 이라 노트북과 iMac 와이파이 주소가 같은 서브넷이다. ping 은 무응답이지만(스텔스 모드로 보임)
  **22번 포트가 열려 있고 배너는 `SSH-2.0-OpenSSH_9.9`** 다. 관리자가 실습 iMac 에 원격 로그인을 이미 켜 두었다.
  5900(화면 공유)은 닫혀 있다.
- Bonjour 로 `_ssh._tcp` 서비스가 146개, `_rfb._tcp`(VNC)는 3개 보인다. 인스턴스 이름은 `c5r8s1.codyssey.kr`
  처럼 좌석 번호 형식이다. 실습실 iMac 전부가 SSH 를 광고하고 있다는 뜻이다.

따라서 노트북 → iMac 은 iMac 와이파이만 켜면 SSH 로 바로 된다. 위 표의 "iMac 에 원격 로그인 켜기" 행은
관리자가 이미 해 둔 상태다(화면 공유는 아님).

```sh
ssh <iMac 계정>@10.19.233.251                     # 노트북에서. 스크립트 실행·파일 전송에 충분
ssh -L 5901:localhost:5900 <iMac 계정>@10.19.233.251   # 화면 공유가 켜지면 터널로 붙일 때
```

- 서버가 광고하는 인증 방식은 `publickey,password,keyboard-interactive`. 그런데 실습 계정(`newids7705`)으로
  **암호를 넣은 뒤 `Connection closed by 10.19.233.251 port 22`** 로 끊긴다. 암호가 틀리면 `Permission denied,
  please try again` 이 나오므로 암호 문제가 아니다. macOS sshd 는 `/etc/pam.d/sshd` 의 `pam_sacl` 로 원격 로그인
  허용 사용자(`com.apple.access_ssh` 그룹)를 검사하고, 여기 없으면 인증 후 `Access denied for user ... by PAM
  account configuration` 으로 연결을 끊는다. 관리자가 원격 로그인을 "다음 사용자만"(기본은 관리자 그룹)으로
  켜 두었을 가능성이 크다. iMac 에서 확인:

  ```sh
  dsmemberutil checkmembership -U newids7705 -G com.apple.access_ssh
  dscl . -read /Groups/com.apple.access_ssh GroupMembership NestedGroups
  ```

  이 그룹에 넣는 것은 관리자만 할 수 있다. 결국 노트북 → iMac 은 관리자에게 SSH 허용 사용자 추가를 요청하거나
  유니버설 컨트롤로 간다.

### 결론 (2026-09-23)

관리자에게 요청하는 것은 불가능하다는 전제라 이 조사는 여기서 중단한다. 관리자 없이 남는 길은 유니버설 컨트롤
뿐이며 실습 iMac 에서 시험하지 않았다. 재개한다면 확인할 것: 위 그룹 확인 결과, 일반 사용자의 접근성 스위치 동작,
유니버설 컨트롤 동작. iMac 와이파이 주소는 DHCP 라 바뀔 수 있다.

### 참고

- Apple, Universal Control: https://support.apple.com/en-us/102459
- MacRumors, Universal Control troubleshooting: https://www.macrumors.com/guide/universal-control-troubleshooting/
- Deskflow wiki, Running on macOS: https://github.com/deskflow/deskflow/wiki/Running-on-macOS
- RustDesk, Mac client: https://rustdesk.com/docs/en/client/mac/
- Jamf community, standard users cannot enable screen recording: https://community.jamf.com/general-discussions-2/macos-monterey-12-3-standard-users-cannot-enable-screen-recording-for-teams-in-privacy-pane-27190
- Addigy, PPPC for Standard Users: https://support.addigy.com/hc/en-us/articles/4403549601043-Privacy-Preferences-Policy-Control-PPPC-for-Standard-Users

## 2026-09-23 조사: 맥북 키보드를 iMac 의 블루투스 키보드로 쓰기

앞 조사에서 SSH 는 관리자 없이 막혔고 유니버설 컨트롤은 Apple 계정과 와이파이가 필요하다. 다른 길로,
맥북을 블루투스 키보드 장치로 보이게 하면 iMac 쪽은 일반 블루투스 키보드를 페어링하는 것과 같아
관리자 권한이 필요 없다. macOS 자체에는 이 기능이 없고 서드파티 앱이 해 준다.

| 앱 | 상태 | Mac 을 대상으로 | 비고 |
|---|---|---|---|
| KeyPad (Mac App Store, id1491684442) | 2.30, 2026-08 갱신, macOS 11 이상, Tahoe 지원 명시 | 가능 | 무료, Pro 평생 4.99달러. 키보드·트랙패드 |
| across | macOS 10.7 이상이라고만 적혀 있음 | 가능 | 윈도우 중심 제품. Sequoia 동작 미확인 |
| Typeeto | 2022-01 이후 갱신 없음 | 가능 | 리뷰에 Big Sur 이후 연결 안 된다는 보고. 제외 |
| BLEVirtualKeyboard (GitHub kingo132) | 오픈소스 | 불가 | TinyPICO 보드가 따로 필요. 제외 |

### 권장: KeyPad

1. 맥북에 KeyPad 를 설치하고 실행한다. 맥북은 내 관리자 계정이라 블루투스·접근성 권한을 바로 켤 수 있다.
2. iMac 에서 시스템 설정 > Bluetooth 를 열면 맥북이 키보드 장치로 보인다. 연결한다. 일반 사용자 계정으로 된다.
3. 맥북에서 KeyPad 를 iMac 으로 전환한 상태에서 타이핑하면 iMac 에 들어간다. 되돌리는 단축키는 앱에서 정한다.

### 주의

- iMac 은 키보드가 하나 붙은 것으로만 보므로 한글 입력은 iMac 쪽 구름 입력기가 처리한다. 맥북의 입력 소스와 무관하다.
- Apple 계정도 와이파이도 필요 없다. 블루투스만 켜면 된다. 유선망·와이파이망 분리 문제도 비켜 간다.
- 화면은 넘어오지 않는다. iMac 화면을 보면서 키보드·트랙패드만 쓰는 용도다.
- 아직 검증하지 않았다. 확인할 것: Sequoia 15.7 실습 iMac 과 실제 페어링, 실습 iMac 이 블루투스 페어링을
  프로파일로 막아 두었는지.

### 참고

- KeyPad, Mac App Store: https://apps.apple.com/us/app/keypad-bluetooth-keyboard/id1491684442?mt=12
- KeyPad 안내: https://bluetooth-keyboard.com/
- across: https://www.acrosscenter.com/
- Typeeto, Mac App Store: https://apps.apple.com/us/app/typeeto-remote-bt-keyboard/id970502923?mt=12
- BLEVirtualKeyboard: https://github.com/kingo132/BLEVirtualKeyboard

## 남은 일 / 주의

- 배포 원본 github.com/newids/imac-setup 에 같은 변경을 반영해야 한다. 5차까지 반영 완료(d9fbe04).
  `index.md` 안내 페이지(2026-09-21 부터 `index.html`)의 확인 절차·문제 해결·동작 원리도 같이 고쳤다.
- 로그인 직후 실습 iMac 에서 다시 확인할 것. 이번 검증은 개발용 Mac 에서 했다.
- 요청 배열이 구름의 모든 배열(16개)이면 덤 배열이 없다. 이때는 요청하지 않은 켜진 배열도 없으므로
  전파가 일어나지 않는다. 실제로는 일어나지 않는다.
- 구름 로마자는 재로그인할 때마다 로그인 에이전트 때문에 다시 켜진다. 스크립트는 로그인 후 한 번 실행하는
  것이 전제다. 재부팅했다면 다시 실행해야 한다.
