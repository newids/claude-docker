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

## 남은 일 / 주의

- 배포 원본 github.com/newids/imac-setup 에 같은 변경을 반영해야 한다. 5차까지 반영 완료(d9fbe04).
  `index.md` 안내 페이지(2026-09-21 부터 `index.html`)의 확인 절차·문제 해결·동작 원리도 같이 고쳤다.
- 로그인 직후 실습 iMac 에서 다시 확인할 것. 이번 검증은 개발용 Mac 에서 했다.
- 요청 배열이 구름의 모든 배열(16개)이면 덤 배열이 없다. 이때는 요청하지 않은 켜진 배열도 없으므로
  전파가 일어나지 않는다. 실제로는 일어나지 않는다.
- 구름 로마자는 재로그인할 때마다 로그인 에이전트 때문에 다시 켜진다. 스크립트는 로그인 후 한 번 실행하는
  것이 전제다. 재부팅했다면 다시 실행해야 한다.
