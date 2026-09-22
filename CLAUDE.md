# CLAUDE.md

이 저장소를 다루는 Claude Code 세션을 위한 안내. 사람이 읽어도 되도록 썼다.

## 저장소 개요

두 가지가 섞여 있다.

1. **Claude Code 개발 컨테이너** (원래 목적)
   - `Dockerfile`, `docker-compose.yml`, `build.sh`, `run.sh`: Ubuntu 기반 이미지에 Claude Code CLI 를 설치한다.
     호스트와 UID/GID 를 맞춘 `user` 계정으로 실행하고 `~/workspace` 를 바인딩한다.
   - `setup.sh`, `zshrc`: 새 머신(컨테이너 밖)에서 zsh 프롬프트, ssh 키(`keys.zip`), git 설정, Claude Code 를 한 번에 준비한다.
   - `encrypt.sh`, `decrypt.sh`, `PAT.enc`: openssl 로 토큰을 암호화해 보관한다. 복호화 결과는 커밋하지 않는다.
2. **iMac 키보드 실습 환경 자동 설정** (`iMac-setup.sh`)
   - 실습실 iMac(macOS Sequoia 15.7 + 구름 입력기 1.13)에서 관리자 권한·UI 조작·재로그인 없이
     fn 키 동작, Caps Lock → fn, 구름 입력 소스(두벌식 + 요청 배열)를 설정한다.
   - 배포 원본은 별도 저장소 github.com/newids/imac-setup 이고 `https://newids.github.io/imac-setup/iMac-setup.sh` 로 제공된다.
     (mac-setup 에서 이름이 바뀌었다. 옛 주소로 밀면 새 위치를 안내하며 그대로 받아 준다.)
     **이 파일을 고치면 imac-setup 저장소에도 같은 변경을 반영해야 한다.** 그쪽 `index.html` 안내 페이지(정적 HTML, `assets/` 에 CSS·JS)도 같이 본다.
   - 설계 결정과 조사 기록은 [docs/iMac-setup-notes.md](docs/iMac-setup-notes.md) 에 있다. 입력 소스 관련 동작을
     바꾸기 전에 반드시 읽을 것. 스크립트 머리말과 3절 주석에도 요약이 있다.

## iMac-setup.sh 작업 규칙

- `/bin/sh`(bash 3.2 POSIX 모드)에서 돌아야 한다. 배열, 프로세스 치환, `[[ ]]` 금지. `curl | sh` 로 실행되므로
  전체를 `main()` 에 담고 마지막 줄에서 호출하는 구조를 유지한다.
- 시스템 API 는 swift 가 아니라 JXA(`osascript -l JavaScript`)로 부른다. swift 는 컴파일 지연과 개발자 도구 의존이 있다.
- 서드파티 입력 소스는 `com.apple.inputsources` `AppleEnabledThirdPartyInputSources` 에만 쓴다.
  `com.apple.HIToolbox` `AppleEnabledInputSources` 에 구름 항목을 넣으면 설정 화면에 중복이 생긴다.
- **설정 파일을 고친 뒤에는 반드시 TIS API 호출로 전파해야 한다.** 파일 갱신, 배포 알림, Darwin 알림, TextInputMenuAgent
  재시작은 이미 실행 중인 앱에 전달되지 않는다. 현재 구현은 쓰지 않는 구름 배열 하나를 덤으로 저장한 뒤
  `TISDisableInputSource` 로 끄는 방식이다. `TISEnableInputSource` 는 서드파티 배열에 대해 System Settings 밖에서는
  무시되거나 확인 창을 띄우므로 쓰지 않는다.
- **덤 배열은 끄기 전에 반드시 켜져 있어야 한다.** 이미 꺼진 것을 끄면 `noErr` 를 돌려주지만 상태 변화가 없어 전파도
  없다. 그래서 덤 배열도 목록 파일에 먼저 써 둔다.
- **구름 로마자(`system`)는 반드시 꺼야 한다.** `tsInputModeDefaultStateKey` 가 참인 배열은 `han2` 와 `system` 뿐이라
  로그인 에이전트가 구름 입력기를 켜면 macOS 가 이 둘을 자동으로 켠다. `system` 은 smRoman + primaryInScript 라서
  켜져 있으면 ABC 자리를 가로채 메뉴 막대에 "로마자"가 뜨고 앱의 입력 소스 전환이 깨진다. 현재 구현은 이것을
  덤 배열로 쓰고, 요청하지 않았는데 켜져 있는 구름 배열이 없어질 때까지 끄기를 되풀이한다.
- 두벌식(`han2`)은 항상 포함한다. 관리자가 설치한 로그인 에이전트(`kr.codyssey.gureum.init`)가 로그인 때 두벌식을 켜고
  선택하는데, 목록에 없으면 실패하거나 확인 창이 뜬다.
- 변경 후에는 아래 절차로 실제 Mac 에서 검증한다. 새 프로세스에서 "켜짐"이 나오는 것만으로는 부족하다.

## 검증 절차 (실제 Mac 필요)

```sh
sh -n iMac-setup.sh                 # 문법
sh iMac-setup.sh --list             # 배열 목록
sh iMac-setup.sh han3final          # 두벌식 + 세벌식 최종
```

마지막 줄에 `실행 중인 앱과 메뉴 막대에도 반영됨` 이 나와야 한다. 이 확인은 설정을 바꾸기 전에 띄운 감시 프로세스가
변경을 받았는지를 본다. 확인용 명령:

```sh
defaults export com.apple.inputsources -                                # 구름 항목 (덤 배열과 로마자는 없어야 함)
defaults read com.apple.HIToolbox AppleEnabledInputSources | grep Gureum # 아무것도 안 나와야 함
```

`plutil -p ~/Library/Preferences/com.apple.inputsources.plist` 는 cfprefsd 가 아직 디스크에 내리지 않은 옛 내용을
보여 줄 수 있다. 확인은 `defaults export` 로 한다.

`log show` 는 zsh 에서 내장 명령 `log` 에 가려지므로 `/usr/bin/log` 로 부른다. 이 터미널에 전체 디스크 접근 권한이 없으면
로그 저장소를 열 수 없다.

## 커밋

- 커밋 메시지는 한국어, 기존 이력의 문체(`iMac-setup.sh: ...`)를 따른다.
- 사용자가 요청할 때만 커밋한다.
