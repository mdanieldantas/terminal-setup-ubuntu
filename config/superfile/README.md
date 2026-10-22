# Configuração do Superfile (`spf`) no `terminal-setup`

Conforme a seção 10 do guia de implementação:

- O comando oficial do Superfile é `spf`.
- Este projeto **não instala um arquivo `config.toml` fictício** para o Superfile.
- Na primeira execução interativa, o próprio `spf` gera seus arquivos de configuração padrão nos diretórios XDG do usuário (`${XDG_CONFIG_HOME:-$HOME/.config}/superfile/config.toml`, `hotkeys.toml` e `theme/`).
- Caso o terminal cliente não possua uma Nerd Font configurada, o usuário pode ajustar `nerdfont = false` no arquivo `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/config.toml` após a primeira execução, ou definir `export RUNEWIDTH_EASTASIAN=0` se houver desalinhamento de bordas em sessões SSH.

