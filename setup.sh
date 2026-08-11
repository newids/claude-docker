cat zshrc >> ~/.zshrc

unzip keys.zip

mv keys/* ~/.ssh

rm -rf keys/

git --version
git config --global user.email "newids@gmail.com"
git config --global user.name "Jeanseok Choi"
git config --global init.defaultBranch main


curl -fsSL https://claude.ai/install.sh | bash

echo "\n\tclaude --dangerously-skip-permissions\n\n"

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
