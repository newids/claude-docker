# 최신 Ubuntu 이미지를 베이스로 사용
FROM ubuntu:latest

# 설치 중 상호작용 프롬프트 방지
ENV DEBIAN_FRONTEND=noninteractive

# 필수 패키지 (git, curl, sudo, 인증서, openssl) 설치
RUN apt update && apt install -y \
    git \
    curl \
    sudo \
    ca-certificates \
    openssl \
    && rm -rf /var/lib/apt/lists/*
    
    # PATH 설정
    ENV PATH="/root/.local/bin:${PATH}"
    
    # 로컬 볼륨 바인딩 시 권한 충돌을 막기 위해 UID, GID를 인자로 받음    
    ARG UID=1000
    ARG GID=1000
    
    # 새로운 사용자 'user' 생성 및 호스트와 UID/GID 일치
    # 컨테이너 내에서 필요시 sudo를 사용할 수 있도록 권한 부여 (비밀번호 없음)
    RUN groupadd -g ${GID} user && \
    useradd -u ${UID} -g ${GID} -m -s /bin/bash user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers    
    # 새로 만든 user로 전환
    USER user
    
    ENV PATH="/home/user/.local/bin:${PATH}"
    
    # 기본 작업 디렉토리 설정 (바인딩될 위치)
    WORKDIR /home/user/workspace
    
# Claude Code CLI 설치 (공식 스크립트 사용)
RUN curl -fsSL https://claude.ai/install.sh | bash
