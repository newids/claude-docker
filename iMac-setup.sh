#!/bin/sh
#
# macOS 키보드 실습 환경 자동 설정 (관리자 권한 불필요, UI 조작 불필요)
#
#   1. 키보드 > fn 키를 누를 때 실행할 동작   -> 입력 소스 변경
#   2. 키보드 단축키 > 보조 키 > Caps Lock 키 -> fn 기능
#   3. 텍스트 입력 > 입력 소스                -> 구름 입력기 추가
#
# 사용법:
#   curl -fsSL https://<host>/iMac-setup.sh | sh                    # 두벌식
#   curl -fsSL https://<host>/iMac-setup.sh | sh -s -- han3final    # 세벌식 최종
#   curl -fsSL https://<host>/iMac-setup.sh | sh -s -- --list       # 배열 목록
#
# curl | sh 로 중간에 끊겨도 부분 실행되지 않도록 전체를 main() 에 담고
# 마지막 줄에서 호출한다. /bin/sh(bash 3.2 POSIX 모드)에서 동작하도록
# 배열과 프로세스 치환은 쓰지 않는다.

set -u

PB=/usr/libexec/PlistBuddy
GUREUM_BUNDLE="org.youknowone.inputmethod.Gureum"

info() { printf '  \033[32m/\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

find_gureum() {
    for d in "$HOME/Library/Input Methods" "/Library/Input Methods"; do
        if [ -d "$d/Gureum.app" ]; then printf '%s\n' "$d/Gureum.app"; return 0; fi
    done
    return 1
}

# 연결된 키보드를 VendorID-ProductID-CountryCode 형식으로 출력한다.
# System Settings 가 쓰는 키 이름과 동일한 형식.
list_keyboards() {
    ioreg -r -c IOHIDInterface -l -w 0 2>/dev/null | awk '
        /^\+-o/               { flush(); v=""; p=""; c=""; kbd=0 }
        /"VendorID" =/        { v = $NF }
        /"ProductID" =/       { p = $NF }
        /"CountryCode" =/     { c = $NF }
        /"PrimaryUsage" = 6$/ { kbd = 1 }
        /"DeviceUsagePage"=1,"DeviceUsage"=6[},]/ { kbd = 1 }
        END { flush() }
        function flush() { if (kbd && v != "" && p != "") print v "-" p "-" (c == "" ? 0 : c) }
    ' | sort -u
}

setup_fn_key() {
    # AppleFnUsageType: 0=아무 동작 안 함 1=입력 소스 변경 2=이모티콘 및 기호 3=받아쓰기
    step "1. fn 키를 누를 때 실행할 동작 -> 입력 소스 변경"
    defaults write com.apple.HIToolbox AppleFnUsageType -int 1
    info "AppleFnUsageType = 1"
}

setup_capslock() {
    # HID usage: Caps Lock = 0x700000039, fn(지구본) = 0xFF00000003
    step "2. 보조 키: Caps Lock -> fn 기능"
    caps=30064771129
    fn=1095216660483
    mapping="({HIDKeyboardModifierMappingSrc=$caps;HIDKeyboardModifierMappingDst=$fn;})"

    kbds=$(list_keyboards)
    if [ -z "$kbds" ]; then
        warn "연결된 키보드를 찾지 못해 Apple Magic Keyboard 기본값으로 적용합니다"
        kbds="1452-591-0"
    fi
    for kbd in $kbds; do
        defaults -currentHost write -g "com.apple.keyboard.modifiermapping.$kbd" "$mapping"
        info "modifiermapping.$kbd"
    done

    # 로그아웃 전에도 즉시 동작하도록 HID 레벨에 적용.
    # 재부팅 이후에는 위 defaults 설정이 인계받는다.
    if hidutil property --set \
        "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":$caps,\"HIDKeyboardModifierMappingDst\":$fn}]}" \
        >/dev/null 2>&1; then
        info "hidutil 즉시 적용 완료"
    fi
}

setup_input_sources() {
    app="$1"; shift
    step "3. 입력 소스에 구름 입력기 추가"

    pl=$(mktemp -t HIToolbox) || die "임시 파일을 만들 수 없습니다"
    defaults export com.apple.HIToolbox "$pl" 2>/dev/null || printf '{}\n' > "$pl"
    $PB -c "Print :AppleEnabledInputSources" "$pl" >/dev/null 2>&1 \
        || $PB -c "Add :AppleEnabledInputSources array" "$pl" >/dev/null

    count=0
    while $PB -c "Print :AppleEnabledInputSources:$count" "$pl" >/dev/null 2>&1; do
        count=$((count + 1))
    done

    for m in "$@"; do
        case "$m" in "$GUREUM_BUNDLE".*) id="$m" ;; *) id="$GUREUM_BUNDLE.$m" ;; esac

        if ! $PB -c "Print :ComponentInputModeDict:tsInputModeListKey:$id" \
                 "$app/Contents/Info.plist" >/dev/null 2>&1; then
            warn "$id - 구름 입력기에 없는 모드입니다. --list 로 확인하세요."
            continue
        fi

        dup=0
        i=0
        while [ "$i" -lt "$count" ]; do
            if [ "$($PB -c "Print :AppleEnabledInputSources:$i:'Input Mode'" "$pl" 2>/dev/null)" = "$id" ]; then
                dup=1
            fi
            i=$((i + 1))
        done
        if [ "$dup" = 1 ]; then info "$id (이미 추가됨)"; continue; fi

        $PB -c "Add :AppleEnabledInputSources:$count dict" \
            -c "Add :AppleEnabledInputSources:$count:InputSourceKind string 'Input Mode'" \
            -c "Add :AppleEnabledInputSources:$count:'Bundle ID' string '$GUREUM_BUNDLE'" \
            -c "Add :AppleEnabledInputSources:$count:'Input Mode' string '$id'" \
            "$pl" >/dev/null
        count=$((count + 1))
        info "$id 추가"
    done

    defaults import com.apple.HIToolbox "$pl"
    rm -f "$pl"
}

apply() {
    step "설정 반영"
    uid=$(id -u)
    for svc in com.apple.TextInputMenuAgent com.apple.TextInputSwitcher; do
        launchctl kickstart -k "gui/$uid/$svc" >/dev/null 2>&1 && info "$svc 재시작"
    done
}

main() {
    [ "$(uname -s)" = "Darwin" ] || die "이 스크립트는 macOS 전용입니다."

    app=$(find_gureum) || die "구름 입력기(Gureum.app)가 설치되어 있지 않습니다.
관리자 설치가 어렵다면 관리자 권한 없이 사용자 영역에만 설치할 수 있습니다:
  mkdir -p ~/Library/Input\\ Methods
  # Gureum.app 을 ~/Library/Input Methods/ 로 복사한 뒤 로그아웃/로그인"

    if [ "${1:-}" = "--list" ]; then
        echo "설치 위치: $app"
        echo "사용 가능한 입력 모드:"
        $PB -c "Print :ComponentInputModeDict:tsInputModeListKey" "$app/Contents/Info.plist" \
            | sed -n 's/^    \('"$GUREUM_BUNDLE"'\.[A-Za-z0-9._-]*\) = Dict {/  \1/p' | sort
        return 0
    fi

    [ "$#" -eq 0 ] && set -- han2

    setup_fn_key
    setup_capslock
    setup_input_sources "$app" "$@"
    apply

    printf '\n\033[1m완료.\033[0m fn 키 동작과 입력 소스는 바로 적용됩니다.\n'
    printf 'Caps Lock -> fn 매핑은 hidutil 로 즉시 적용되며, 재부팅 후에도 유지하려면\n'
    printf '한 번 로그아웃 후 다시 로그인하세요.\n'
}

main "$@"
