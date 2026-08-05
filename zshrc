alias l='ls -l'
alias ll='ls -alF'

# 1. vcs_info 모듈 로드 및 초기화
autoload -Uz vcs_info
precmd() { vcs_info }

# 2. Git 브랜치 표시 형식 설정
# %b: 브랜치 이름, %u: 스테이징되지 않은 변경사항, %c: 스테이징된 변경사항
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '%F{yellow}(%b%u%c)%f'
zstyle ':vcs_info:git:*' actionformats '%F{red}(%b|%a)%f'

# 3. 변경사항 상태 기호 설정
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '%F{red}*%f'    # 수정한 파일이 있을 때 *
zstyle ':vcs_info:git:*' stagedstr '%F{green}+%f'      # git add된 파일이 있을 때 +

# 4. PROMPT 변수에 $vcs_info_msg_0_ 포함하기
setopt prompt_subst
PROMPT='%F{cyan}%n@%m%f:%F{blue}%1~%f ${vcs_info_msg_0_} %# '
