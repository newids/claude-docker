# 새 머신(컨테이너 밖)에 zsh 프롬프트, ssh 키, git, Claude Code 를 한 번에 준비한다.
# 여러 번 실행해도 같은 결과가 되도록 썼다.

# --- zsh 프롬프트 -----------------------------------------------------------
grep -qF 'claude-docker zshrc' ~/.zshrc 2>/dev/null || {
    printf '\n# --- claude-docker zshrc ---\n' >> ~/.zshrc
    cat zshrc >> ~/.zshrc
}

# --- ssh 키 ----------------------------------------------------------------
# keys.zip 에는 키 파일만 들어 있고 config 와 known_hosts 는 없다. 그대로 두면
#   - known_hosts 가 없어 첫 접속에서 호스트 키를 확인하겠냐고 묻는다. curl | sh 나
#     스크립트 안에서는 stdin 이 막혀 있어 대답할 수 없고, 그러면 푸시가 그냥 실패한다.
#   - config 가 없어 기본 이름(id_ed25519 등)이 아닌 키는 쓰이지 않는다.
# 그래서 둘 다 여기서 만들어 준다.
mkdir -p ~/.ssh && chmod 700 ~/.ssh

if [ -f keys.zip ]; then
    unzip -o keys.zip && mv -f keys/* ~/.ssh/ && rm -rf keys/
fi
chmod 600 ~/.ssh/id_* 2>/dev/null
chmod 644 ~/.ssh/id_*.pub 2>/dev/null

# github.com 호스트 키를 미리 넣는다. 받아 온 키의 지문을 GitHub 이 공개한 값과
# 대조하므로 "묻지 않고 그냥 믿기"(StrictHostKeyChecking=no)와는 다르다.
# https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
GITHUB_FP_ED25519="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    hostkey=$(mktemp)
    ssh-keyscan -t ed25519 github.com > "$hostkey" 2>/dev/null
    fp=$(ssh-keygen -lf "$hostkey" 2>/dev/null | awk '{print $2}')
    if [ "$fp" = "$GITHUB_FP_ED25519" ]; then
        cat "$hostkey" >> ~/.ssh/known_hosts
        echo "  / known_hosts 에 github.com 추가"
    else
        echo "  ! github.com 호스트 키 지문이 공개된 값과 다릅니다 (${fp:-받지 못함}). 직접 확인하세요" >&2
    fi
    rm -f "$hostkey"
fi
touch ~/.ssh/known_hosts && chmod 644 ~/.ssh/known_hosts

# ssh config. 키 이름이 기본값이 아니어도, 다른 키가 먼저 시도되어도 이 키를 쓴다.
if ! grep -q '^Host github\.com' ~/.ssh/config 2>/dev/null; then
    {
        echo "Host github.com"
        echo "  HostName github.com"
        echo "  User git"
        echo "  IdentityFile ~/.ssh/id_ed25519"
        echo "  IdentitiesOnly yes"
        echo "  AddKeysToAgent yes"
        [ "$(uname -s)" = "Darwin" ] && echo "  UseKeychain yes"
    } >> ~/.ssh/config
    echo "  / ~/.ssh/config 에 github.com 항목 추가"
fi
chmod 600 ~/.ssh/config

# --- git -------------------------------------------------------------------
git --version
git config --global user.email "newids@gmail.com"
git config --global user.name "Jeanseok Choi"
git config --global init.defaultBranch main

# 이미 받아 둔 저장소의 원격 주소가 https 여도 ssh 키로 푸시되게 한다.
# https 로 푸시하면 git 이 사용자명과 토큰을 묻는데, 비대화형 셸에서는 대답할 수 없어
# "could not read Username for 'https://github.com': Device not configured" 로 실패한다.
git config --global url."git@github.com:".insteadOf "https://github.com/"

# 확인. ssh -T 는 성공해도 종료 코드가 1 이므로 출력으로 판단한다.
if ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    echo "  / GitHub ssh 인증 확인"
else
    echo "  ! GitHub ssh 인증 실패. 공개키(~/.ssh/id_ed25519.pub)를 GitHub 계정에 등록했는지 확인하세요" >&2
fi

# --- Claude Code -----------------------------------------------------------
curl -fsSL https://claude.ai/install.sh | bash

grep -qF '.local/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

printf '\n\tclaude --dangerously-skip-permissions\n\n'
