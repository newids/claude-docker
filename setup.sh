cat zshrc >> ~/.zshrc

unzip keys.zip

mv keys/* ~/.ssh

rm -rf keys/

git --version
git config --global user.email "newids@gmail.com"
git config --global user.name "Jeanseok Choi"
git config --global init.defaultBranch main

source ~/.zshrc

