# Manual do usuário — Terminal Setup Ubuntu

> Guia operacional para instalar, utilizar, diagnosticar e restaurar o ambiente de terminal.

| Campo | Informação |
|---|---|
| Projeto | terminal-setup-ubuntu |
| Revisão deste manual | 1.0 — 22 de outubro de 2026 |
| Plataforma-alvo inicial | Ubuntu 24.04 LTS, amd64 |
| Ambiente de desenvolvimento do responsável | Aurora Linux |
| Estado informado | Testes locais e em containers aprovados; CI remoto e licença pendentes na última atualização |
| Público | Usuários de Linux, administradores de homelab e desenvolvedores |

## Sobre a precisão deste manual

Este documento foi preparado a partir do guia de implementação e dos relatórios finais do Antigravity fornecidos pelo responsável, e passou por **conferência documental direta contra o checkout final realizada pelo Antigravity em 22/10/2026** (`install-terminal.sh`, `doctor.sh`, `uninstall-terminal.sh`, `scripts/install-system-packages.sh`, `lib/*.sh`, `config/*`, `profiles/*.conf` e `versions/*.lock.json`). Trata-se de conferência documental: **nenhum teste novo foi executado nesta revisão do manual** (os resultados de testes citados referem-se às rodadas de validação já concluídas).

Os comandos de uso demonstrados nos relatórios são identificados ao longo do manual e correspondem ao parser atual documentado nas ajudas (`--help`) dos scripts e em [`docs/parametros.md`](parametros.md). Em caso de dúvida ao operar em uma máquina real, confira sempre `--help` e `--dry-run` antes de aplicar; não adapte comandos destrutivos por tentativa e erro.

O antigo protótipo WSL/Ubuntu não é a fonte de opções deste manual.

Este manual não concede autorização a uma IA para executar instalações ou modificar sistemas.

## Índice

1. [Visão geral](#1-visão-geral)
2. [Regras de operação e ambientes](#2-regras-de-operação-e-ambientes)
3. [Início rápido no Docker](#3-início-rápido-no-docker)
4. [Escolha do perfil](#4-escolha-do-perfil)
5. [Preparação e ajuda](#5-preparação-e-ajuda)
6. [Instalação em Ubuntu](#6-instalação-em-ubuntu)
7. [Construção e uso de imagens Docker](#7-construção-e-uso-de-imagens-docker)
8. [Ferramentas no dia a dia](#8-ferramentas-no-dia-a-dia)
9. [Superfile](#9-superfile)
10. [Preferências e personalização](#10-preferências-e-personalização)
11. [Estado, logs e backups](#11-estado-logs-e-backups)
12. [Diagnóstico](#12-diagnóstico)
13. [Desinstalação e restauração](#13-desinstalação-e-restauração)
14. [Manutenção e atualização](#14-manutenção-e-atualização)
15. [Solução de problemas](#15-solução-de-problemas)
16. [Qualidade e suporte](#16-qualidade-e-suporte)
17. [Checklists](#17-checklists)
18. [Referências](#18-referências)

## 1. Visão geral

O Terminal Setup Ubuntu automatiza a preparação de um ambiente de terminal com Zsh, Starship, ferramentas CLI e configurações de usuário.

Ele possui três pontos de entrada principais de espaço do usuário na raiz e um helper administrativo separado em `scripts/`:

| Arquivo | Responsabilidade |
|---|---|
| `install-terminal.sh` | Planejar e aplicar a instalação/configuração de usuário (`UID != 0`) |
| `doctor.sh` | Consultar o estado do ambiente em modo somente leitura e apontar problemas |
| `uninstall-terminal.sh` | Desfazer recursos gerenciados conforme manifesto e política de restauração (`UID != 0`) |
| `scripts/install-system-packages.sh` | Instalar exclusivamente os pacotes APT previstos na allowlist do projeto (`UID 0`) |

O projeto não instala Docker Engine, bancos de dados ou serviços web. O perfil `server` não configura SSH, firewall, Fail2ban ou atualizações automáticas do sistema.

### Modelo de privilégios

- Configurações pessoais e ferramentas de usuário: usuário comum.
- Pacotes Ubuntu: helper administrativo, com privilégio temporário quando necessário.
- Docker build: instalação administrativa dentro da imagem, seguida da configuração como `dev`.
- Container final: usuário não-root.

Não execute o instalador principal com `sudo bash` e não cole seu corpo inteiro no terminal. Execute o arquivo com Bash.

## 2. Regras de operação e ambientes

Os blocos deste manual indicam onde executar:

| Identificação | Onde executar |
|---|---|
| HOST | Konsole ou outro terminal do Aurora/computador que controla o Docker |
| CONTAINER | Terminal já aberto dentro do ambiente Ubuntu Docker |
| UBUNTU | Usuário comum em uma máquina Ubuntu-alvo |
| REPOSITÓRIO | Terminal posicionado na raiz do checkout correto |

### Atenção ao Aurora

O Aurora pode hospedar o código e executar Docker. Isso não transforma o host em destino do instalador APT. Não rode o helper de pacotes Ubuntu no Aurora.

### Container não é VM

Os testes relatados foram executados em containers Ubuntu 24.04 amd64. Não comprovam boot, serviços systemd, sessão PAM ou troca interativa de shell em servidor/VM.

### Caminhos e placeholders

`/CAMINHO/DO/PROJETO` representa a pasta real do seu checkout. Substitua antes de executar. Não digite os símbolos de prompt como `$`, `#` ou `❯` junto com os comandos.

O caminho utilizado pelo responsável durante o desenvolvimento foi:

```text
/run/media/dan/FAB4D7F8B4D7B57B/repos/01-Linux/terminal-setup-ubuntu
```

Esse caminho não é requisito e não deve ser copiado para outro computador sem adaptação.

## 3. Início rápido no Docker

Este é o caminho mais direto para experimentar a imagem final já construída no computador do responsável.

### 3.1 Confirmar que a imagem existe — HOST

```bash
docker image inspect terminal-setup:ts-p5-developer-20261022-7eb4ba03 --format '{{.Id}} {{.Config.User}}'
```

O comando consulta a imagem local e mostra seu ID e usuário configurado. Não instala o projeto no host.

Se a tag não existir nesse computador, use a seção 7 para construir a imagem. Não há garantia de que essa tag esteja publicada em um registry.

### 3.2 Abrir sessão descartável — HOST

```bash
docker run --rm -it --network none terminal-setup:ts-p5-developer-20261022-7eb4ba03
```

- `--rm`: remove o container ao encerrar.
- `-it`: conecta o terminal de forma interativa.
- `--network none`: desativa conectividade externa do container.
- Não há `-v` ou `--mount`: suas pastas do host não são disponibilizadas pelo comando.

A imagem permanece após a saída. Arquivos criados apenas nessa sessão serão perdidos quando o container for removido.

### 3.3 Conferir o ambiente — CONTAINER

```bash
id
printf 'HOME=%s\nSHELL=%s\n' "$HOME" "$SHELL"
bash /opt/terminal-setup/doctor.sh --profile developer
```

`id` mostra a identidade efetiva. As variáveis mostram o HOME e o shell declarado no ambiente; a variável SHELL, sozinha, não identifica necessariamente o processo atual. O `doctor` executa o diagnóstico do projeto.

Na imagem relatada, o usuário foi `dev`, UID/GID `1001:1001` e HOME `/home/dev`. UID 1001 foi consequência de colisão com a conta `ubuntu` da base, não um requisito universal.

### 3.4 Experimentar arquivos — CONTAINER

```bash
mkdir -p "$HOME/laboratorio-terminal"
cd "$HOME/laboratorio-terminal"
printf '%s\n' 'Primeiro arquivo de exemplo.' > exemplo-1.txt
printf '%s\n' 'Segundo arquivo para navegação no Superfile.' > exemplo-2.txt
spf
```

Cria uma pasta de laboratório e dois textos para navegar. As duas linhas com `>` substituem os arquivos caso já existam; use esses nomes somente para testes.

### 3.5 Sair — CONTAINER

Feche o Superfile e execute:

```bash
exit
```

O container descartável será removido. Isso não remove a imagem nem o repositório do host.

## 4. Escolha do perfil

| Perfil | Finalidade | Componentes principais informados |
|---|---|---|
| `minimal` | Terminal enxuto | Zsh, Git, Nano, curl, CA certificates, jq, Starship plain, fzf, ripgrep, bat |
| `developer` | Ambiente de trabalho de desenvolvimento | minimal + fd, tmux, zoxide, eza, Superfile e três plugins Zsh |
| `server` | Produtividade na administração por terminal | minimal + fd, jq, tmux, zoxide, btop, autosuggestions e history-substring-search |

### Componentes opcionais

- `developer`: btop e vi-mode não são obrigatórios por padrão.
- `server`: Superfile, eza, syntax-highlighting e vi-mode são opcionais.
- `minimal`: não inclui os plugins por padrão; vi-mode é uma escolha explícita.
- `zsh-vi-mode` permanece desligado por padrão.

O conjunto exato deve ser conferido em `profiles/*.conf` e [`docs/perfis.md`](perfis.md) da revisão local. Os perfis não representam níveis de hardening.

## 5. Preparação e ajuda

### 5.1 Entrar na pasta — REPOSITÓRIO

```bash
cd /CAMINHO/DO/PROJETO
pwd
ls
```

`cd` seleciona o checkout; `pwd` confirma a pasta e `ls` lista os arquivos. Verifique se existem `install-terminal.sh`, `doctor.sh`, `lib/`, `config/` e `profiles/`.

Não há URL pública confirmada neste manual. Obtenha o repositório pelo endereço real definido pelo responsável, não por URLs de exemplo com SEU-USUARIO.

### 5.2 Consultar as interfaces

```bash
bash ./install-terminal.sh --help
bash ./doctor.sh --help
bash ./uninstall-terminal.sh --help
```

Esses comandos mostram as opções da versão local. Executar com `bash` evita depender do bit executável do checkout, o que é útil em armazenamento compartilhado Windows/Linux.

Não altere `core.filemode`, permissões recursivas ou opções de montagem NTFS só para executar os exemplos deste manual.

### 5.3 Ver a versão

```bash
bash ./install-terminal.sh --version
```

Mostra a versão declarada pelo projeto. Não confundir com a versão de Starship ou Ubuntu.

## 6. Instalação em Ubuntu

> Execute esta seção somente no Ubuntu-alvo, como usuário comum. Integração em VM/servidor com boot completo ainda estava pendente no último relatório.

### 6.1 Planejar antes de aplicar — UBUNTU / REPOSITÓRIO

```bash
bash ./install-terminal.sh --profile developer --dry-run
```

O contrato do projeto exige que a simulação apresente o plano sem instalar pacotes, gravar configurações, criar logs ou fazer downloads. Revise ferramentas, destinos e conflitos antes de executar a instalação.

### 6.2 Instalação interativa

```bash
bash ./install-terminal.sh --profile developer
```

O instalador pode perguntar sobre configurações pessoais e solicitar autenticação administrativa por meio do mecanismo apropriado para instalar pacotes.

A senha administrativa pertence ao usuário da máquina Ubuntu. Não é automaticamente a senha do Aurora, GitHub ou de outro container.

Leia cada confirmação. Instalar Git não exige definir identidade global, e instalar Zsh não exige trocar imediatamente o shell de login.

### 6.3 Servidor com Superfile opcional

```bash
bash ./install-terminal.sh --profile server --include superfile --dry-run
```

Planeja o perfil server com Superfile acrescentado. Após revisar, o mesmo comando sem `--dry-run` solicita a aplicação.

Isso não instala nem endurece SSH/firewall.

### 6.4 Instalar somente Superfile

```bash
bash ./install-terminal.sh --only superfile --dry-run
```

Após revisar o plano:

```bash
bash ./install-terminal.sh --only superfile
```

O projeto resolve automaticamente as dependências obrigatórias do Superfile (`ca-certificates`, `curl` e `jq`). No parser implementado (`lib/arguments.sh`), `--only` é mutuamente exclusivo com seleção explícita de `--profile`, `--include` e `--exclude` (inclusive quando definidos via `--config`), retornando código `2` em caso de combinação inválida.

### 6.5 Modo sem perguntas

```bash
bash ./install-terminal.sh \
  --profile developer \
  --non-interactive \
  --skip-system-packages \
  --git-identity skip \
  --change-shell no
```

Esse fluxo foi utilizado nos containers. Pressupõe pacotes de sistema já preparados. Não é uma alternativa mágica ao privilégio administrativo quando faltam pacotes.

- `--non-interactive`: não deve solicitar respostas.
- `--skip-system-packages`: não executa instalação administrativa.
- `--git-identity skip`: preserva a decisão de identidade.
- `--change-shell no`: não troca o shell de login.

`--yes` e `--non-interactive` têm funções diferentes. Não use `--yes` para supor que prompts de dados pessoais, sudo e troca de shell desaparecerão.

### 6.6 Quando não há sudo disponível

A arquitetura prevê execução em duas etapas: o administrador instala primeiro os pacotes APT pelo helper e o usuário comum configura o próprio `HOME` depois.

Consulte a ajuda do helper:

```bash
bash ./scripts/install-system-packages.sh --help
```

Não execute o helper no host Aurora. No Ubuntu 24.04 `amd64` alvo, o helper exige `UID 0` (`root`) diretamente e **não** utiliza flag `--allow-root`. Suas opções implementadas são `--profile <minimal|developer|server>`, `--packages <pkg1,pkg2,...>`, `--dry-run` e `-h`/`--help`:

```bash
# Etapa 1 — Administrador (root/sudo) no Ubuntu 24.04 amd64:
sudo bash ./scripts/install-system-packages.sh --profile developer

# Etapa 2 — Usuário comum (UID != 0) no Ubuntu 24.04 amd64:
bash ./install-terminal.sh --profile developer --skip-system-packages
```

### 6.7 Ativar e verificar Zsh

Se Zsh foi instalado, mas você optou por não trocar o shell padrão:

```bash
zsh
```

Abre um Zsh filho; `exit` retorna ao shell anterior. Não repita esse comando dentro de Zsh sem necessidade, para não empilhar sessões.

Abra uma nova sessão de login quando fizer uma troca de shell aprovada. Não execute `source install-terminal.sh` nem use `.zshrc` de Zsh como script Bash.

## 7. Construção e uso de imagens Docker

### 7.1 Construir uma imagem própria — HOST / REPOSITÓRIO

Antes, confirme que a tag escolhida não representa algo que deseja preservar:

```bash
docker image ls terminal-setup
```

Construção do perfil developer:

```bash
docker build -f docker/Dockerfile --build-arg PROFILE=developer -t terminal-setup:developer-local .
```

O ponto final seleciona a raiz atual como contexto. O build baixa dependências e executa o Dockerfile dentro do ambiente de construção. Cria imagem/cache no armazenamento Docker; não instala APT no sistema base do host.

Construção dos outros perfis:

```bash
docker build -f docker/Dockerfile --build-arg PROFILE=minimal -t terminal-setup:minimal-local .
docker build -f docker/Dockerfile --build-arg PROFILE=server -t terminal-setup:server-local .
```

Cada comando cria ou atualiza sua própria tag. Se quiser preservar versões anteriores, escolha tags novas antes de construir.

### 7.2 Executar sem persistência

```bash
docker run --rm -it --network none terminal-setup:developer-local
```

Use para experimentação descartável. Superfile administra os arquivos disponíveis no container; ele não enxerga automaticamente os arquivos do host.

### 7.3 Manter um laboratório entre sessões

Primeiro confirme que o nome não existe:

```bash
docker ps -a --filter name=terminal-lab
```

Se estiver livre, crie sem `--rm`:

```bash
docker run -it --network none --name terminal-lab terminal-setup:developer-local
```

Depois de sair, reabra:

```bash
docker start -ai terminal-lab
```

Os arquivos da camada gravável permanecem enquanto o container existir. Isso não é backup e não acompanha automaticamente uma imagem reconstruída.

Remoção deliberada, depois de salvar o que importa e encerrar a sessão:

```bash
docker rm terminal-lab
```

Remove esse container parado e seus dados internos. Não use `-f` para encerrar trabalho ativo por conveniência.

### 7.4 Compose

Inspecione a configuração resolvida:

```bash
docker compose -f docker/compose.yaml config
```

Pode haver interpolação de variáveis ou leitura de configuração local; não publique essa saída sem revisão.

Construção e execução:

```bash
docker compose -f docker/compose.yaml build terminal
docker compose -f docker/compose.yaml run --rm terminal
```

O Compose padrão apresentado no projeto não bloqueia rede como os overrides dos testes. Para um teste estritamente offline, use o `docker run --network none` mostrado anteriormente.

### 7.5 Volumes e arquivos do host

Este manual não habilita montagens por padrão. Um bind mount gravável permitiria que operações no Superfile ou no shell alterassem os arquivos montados do host.

Antes de habilitar volumes:

1. Escolha uma pasta de laboratório dedicada.
2. Faça backup.
3. Decida se o acesso pode ser somente leitura.
4. Revise UID/GID e permissões.
5. Nunca monte todo o HOME, `/`, `/root` ou o socket Docker para um simples teste de terminal.

Consulte [`docs/docker.md`](docker.md) antes de alterar o Compose.

## 8. Ferramentas no dia a dia

Os exemplos não dependem de aliases pessoais. Execute em uma pasta de trabalho cujo conteúdo possa examinar.

| Comando | Uso |
|---|---|
| `pwd` | Mostrar a pasta atual |
| `ls -la` | Listar arquivos, inclusive ocultos |
| `bat exemplo-1.txt` | Ler texto com apresentação enriquecida |
| `rg 'exemplo' .` | Buscar texto recursivamente |
| `fd '\.txt$' .` | Procurar nomes de arquivos pelo padrão |
| `fzf` | Abrir seleção fuzzy de arquivos/listas conforme a entrada |
| `jq . arquivo.json` | Validar e formatar a visualização de JSON |
| `eza -la` | Listar com eza sem substituir ls |
| `spf` | Abrir o Superfile |
| `btop` | Abrir o monitor quando instalado |

`fd`, `eza`, `btop` e outras ferramentas dependem do perfil. Em Ubuntu, os executáveis originais podem ser `fdfind` e `batcat`; o projeto relatou links `fd` e `bat` em `~/.local/bin` quando não há colisão.

Não use dados sensíveis apenas para experimentar ferramentas de histórico ou preview.

### zoxide

Depois que a integração tiver registrado diretórios visitados, `z nome` permite navegar por aproximação. Se `z` não existir, confira a integração Zsh e o perfil; não assuma que instalar o binário ativa qualquer shell existente.

### tmux

Criar sessão de trabalho:

```bash
tmux new-session -s trabalho
```

Desanexar usando as teclas padrão: `Ctrl+b`, solte e pressione `d`.

Reconectar:

```bash
tmux attach-session -t trabalho
```

Liste sessões com `tmux list-sessions`.

A configuração instalada pelo projeto ([`config/tmux/tmux.conf`](../config/tmux/tmux.conf) -> `~/.config/tmux/tmux.conf`) mantém o prefixo padrão `Ctrl+b`, ativa suporte a mouse (`mouse on`), inicia a numeração de janelas e painéis em `1` e adiciona os atalhos:
- `Ctrl+b` seguido de `|` (`split-window -h`): dividir a janela em **painéis lado a lado**, mantendo o diretório atual;
- `Ctrl+b` seguido de `-` (`split-window -v`): dividir a janela em **painéis um acima do outro**, mantendo o diretório atual;
- `Ctrl+b` seguido de `r`: recarregar `~/.config/tmux/tmux.conf`.

Dentro de um container, `tmux` não mantém processos vivos depois que o container para ou é removido.

## 9. Superfile

### Abrir

```bash
spf
```

O diretório inicial é o contexto em que você abriu a ferramenta. Comece no laboratório descrito na seção 3, não em dados importantes.

### Navegação básica

Os atalhos padrão publicados pelo Superfile incluem:

- Setas ou `j`/`k`: mover seleção.
- `Enter`: confirmar/abrir o item selecionado.
- `q` ou `Esc`: sair do modo/modal ou do aplicativo, conforme o contexto.
- `Tab`: alternar painéis quando aplicável.

Atalhos podem mudar com configuração e versão. Consulte a ajuda exibida e o tutorial oficial antes de copiar, mover, excluir ou renomear dados.

Não há necessidade de um alias `cat=bat` ou `ls=eza` para usar Superfile.

### Configuração e fontes

O projeto não deve criar um config.toml fictício. O local e o schema precisam seguir a versão upstream utilizada.

Se ícones aparecerem como quadrados em uma sessão SSH, revise a fonte do terminal cliente, como Konsole no Aurora. Instalar fonte no servidor não altera automaticamente a fonte usada pelo seu terminal local.

O modo plain reduz a dependência de símbolos especiais no prompt. Isso não significa que qualquer TUI ficará visualmente idêntica em todos os emuladores de terminal.

## 10. Preferências e personalização

### Interface de configuração

O contrato prevê `--config` para ler arquivo restrito `CHAVE=valor`. Confira a lista e sintaxe no arquivo de exemplo e na ajuda antes de preencher.

```bash
cat examples/terminal.conf.example
bash ./install-terminal.sh --help
```

Se o arquivo local ainda não existir, copie o exemplo:

```bash
cp -i examples/terminal.conf.example terminal.conf
nano terminal.conf
```

`cp -i` pergunta antes de sobrescrever. Nano edita o arquivo local. Não coloque senhas, tokens ou chaves privadas nele.

Planeje com o arquivo:

```bash
bash ./install-terminal.sh --config "$PWD/terminal.conf" --dry-run
```

O parser não deve executar shell, expandir `$()` ou carregar o arquivo com `source`. Não escreva comandos nesse arquivo.

### Conflitos

As políticas previstas são:

| Política | Intenção |
|---|---|
| `ask` | Perguntar no modo interativo |
| `keep` | Preservar arquivo existente |
| `backup-replace` | Fazer backup antes de substituir |

Exemplo de planejamento conservador:

```bash
bash ./install-terminal.sh --profile developer --on-conflict keep --dry-run
```

Preservar um arquivo existente pode impedir a ativação de uma configuração nova; o diagnóstico deve distinguir preservação intencional de falha.

### Arquivos instalados x templates

- `config/` no repositório contém os modelos.
- Os arquivos sob seu HOME são a instalação efetiva.
- Editar o template não atualiza automaticamente containers ou instalações existentes.
- Editar o arquivo instalado cria uma alteração local que deve ser preservada ou tratada como conflito em futuras execuções.

Raízes XDG/ZDOTDIR que sejam symlinks têm restrições relatadas no projeto. Não substitua seus diretórios pessoais para contornar a validação; consulte [`docs/seguranca.md`](seguranca.md) e escolha um destino suportado.

## 11. Estado, logs e backups

O projeto utiliza o estado do usuário:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/
├── lock/
├── logs/
├── backups/
└── manifests/
```

Na imagem developer relatada:

```text
/home/dev/.local/state/terminal-setup/
```

Inspeção somente leitura:

```bash
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup"
printf 'Estado do projeto: %s\n' "$STATE_DIR"
ls -la "$STATE_DIR"
```

O estado pode não existir antes da primeira instalação ou após uma operação apenas de simulação.

### Função de cada parte

- Lock (`lock/`): controle de concorrência durante execuções efetivas.
- Logs (`logs/`): eventos e resultados de execução (permissão `0600`, sem gravar nome/e-mail Git).
- Backups (`backups/`): estado anterior dos arquivos substituídos.
- Manifestos (`manifests/`): recursos gerenciados e informações necessárias à validação/restauração (permissão `0600`).

Não edite manualmente os manifestos para fazer uma restauração passar. Não apague o estado enquanto pretende desfazer uma instalação.

Backups de configuração não substituem backup de documentos, projetos, bancos de dados ou volume do container.

## 12. Diagnóstico

### Relatório humano

Em instalação local, a partir do repositório:

```bash
bash ./doctor.sh --profile developer
```

Dentro da imagem:

```bash
bash /opt/terminal-setup/doctor.sh --profile developer
```

### JSON

```bash
bash ./doctor.sh --profile developer --json
```

Para leitura formatada, quando jq estiver disponível:

```bash
bash ./doctor.sh --profile developer --json | jq .
```

Um pipeline pode mudar o código de saída observado pelo shell. Para registrar o resultado do doctor sem ambiguidade, execute-o diretamente e depois consulte `echo "$?"` imediatamente, antes de outro comando.

### Strict

```bash
bash ./doctor.sh --profile developer --strict
```

No `doctor.sh` implementado, se `--profile` for omitido o padrão avaliado é `minimal`. Com `--strict`, qualquer verificação reportada como `warning` (como `~/.local/bin` fora do `PATH` atual, shell de login diferente de Zsh, arquivo mantido por `kept_existing` ou ferramenta opcional do perfil ausente) faz o comando retornar código de saída `1`. Sem `--strict`, apenas erros em requisitos obrigatórios ou falhas de sintaxe/integridade retornam `1`.

Doctor é estritamente somente leitura: não instala, não repara, não baixa conteúdo, não cria logs e não solicita `sudo`.

## 13. Desinstalação e restauração

### 13.1 Consultar antes de agir

```bash
bash ./uninstall-terminal.sh --help
bash ./uninstall-terminal.sh --dry-run
```

A simulação permite examinar o plano. Confira quais recursos seriam removidos/restaurados e os conflitos encontrados.

### 13.2 Executar de forma interativa

```bash
bash ./uninstall-terminal.sh
```

Use somente depois de revisar a ajuda, a simulação e os backups. A interface interativa vem do contrato do projeto; confirme as perguntas efetivas da revisão local antes de aprovar.

O fluxo não interativo foi demonstrado em HOME temporário nos testes, mas não é o padrão recomendado para a primeira restauração dos seus arquivos reais.

### 13.3 Selecionar uma instalação

O script `uninstall-terminal.sh` implementa a opção `--restore <INSTALL_ID>` (além de `--dry-run`, `--non-interactive` e `--on-modified keep`). Para inspecionar e restaurar um manifesto específico:

```bash
# Simular a restauração de um manifesto específico:
bash ./uninstall-terminal.sh --restore <INSTALL_ID> --dry-run

# Executar a restauração interativa daquele manifesto:
bash ./uninstall-terminal.sh --restore <INSTALL_ID>
```

Consulte [`docs/backup-restauracao.md`](backup-restauracao.md) e confira o conteúdo do arquivo em `${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/manifests/<INSTALL_ID>.json` antes de restaurar; não escolha apenas pelo mais recente sem verificar.

### Limites

- Não remove pacotes APT por padrão.
- Não deve apagar arquivos desconhecidos.
- Arquivos editados após instalação devem ser preservados ou apresentados como conflito.
- O shell de login merece tratamento separado: não remova o executável Zsh enquanto ele for necessário ao login.
- Não use `rm -rf ~/.config` ou apague toda a pasta de estado como substituto da desinstalação.

## 14. Manutenção e atualização

### Reexecutar não significa atualizar tudo

O projeto possui locks para ferramentas externas e plugins. Repetir o instalador deve respeitar a revisão utilizada e a política de conflitos; não significa buscar automaticamente qualquer release nova.

### Antes de atualizar o projeto

1. Verifique alterações locais com `git status` e `git diff`.
2. Leia CHANGELOG e documentação da revisão nova.
3. Preserve seus dados e configurações.
4. Revise mudanças de versões/checksums e dependências.
5. Teste em container ou VM antes de uma máquina de trabalho.
6. Execute o plano `--dry-run` no destino suportado.

Não execute git pull automaticamente se houver alterações locais não compreendidas. Este manual não publica mudanças, cria commits ou executa push por você.

### Atualizar uma imagem

Reconstrua com tag nova, teste e crie um container novo. Containers já existentes não recebem automaticamente o conteúdo de uma imagem reconstruída.

Não use docker commit como substituto principal do Dockerfile/locks para distribuir o projeto.

### Espaço em disco

Consulta de uso:

```bash
docker system df
```

Mostra uso de imagens, containers, volumes e cache. Não remove nada.

Não use `docker system prune`, `docker volume prune` ou exclusões em massa para limpar apenas este projeto. Identifique o recurso e confirme que ele não guarda dados importantes antes de remover.

## 15. Solução de problemas

| Sintoma | Verificação | Ação inicial |
|---|---|---|
| Imagem não encontrada | `docker image ls terminal-setup` | Usar tag existente ou construir pelo Dockerfile |
| Instalador recusa root | `id` | Executar como usuário comum; pacotes via helper separado |
| Plataforma não suportada | `cat /etc/os-release` | Não forçar instalação no Aurora; usar Ubuntu-alvo |
| Falha de sudo | Usuário e máquina em que a senha foi definida | Testar autenticação no Ubuntu, sem gravar senha no script |
| `bat`/`fd` ausentes | `command -v bat batcat fd fdfind` | Conferir perfil, PATH e colisões de links com doctor |
| Prompt não aparece | Shell efetivo e arquivos carregados | Abrir nova sessão ou testar Zsh filho; não sourcear Zsh em Bash |
| Ícones ilegíveis | Fonte do terminal cliente | Usar plain ou revisar Nerd Font no cliente |
| Root do manifesto divergente | Dono real e ambiente atual | Não editar manifesto; executar como usuário correto |
| Arquivo mantido/kept_existing | Política de conflito | Revisar antes de optar por backup-replace |
| ZDOTDIR/XDG recusado | Links simbólicos nos caminhos | Consultar limitação documentada; não desativar validação |
| Download com checksum divergente | URL, versão e hash esperado | Parar; não atualizar o hash apenas para passar |
| Falha de DNS no build | Log exato do comando | Distinguir restrição do executor de problema do host |
| Download tenta ocorrer no teste offline | Log do container | Investigar dependência/reexecução; não liberar rede automaticamente |
| Lock de execução persistente | Processo ativo e estado | Ler procedimento documentado; não apagar lock durante execução |

### Coletar um relato útil

Informe:

1. Revisão do projeto e perfil.
2. Ambiente: host, container ou VM.
3. Comando exato.
4. Código de saída.
5. Trecho relevante do erro.
6. Saída do doctor, revisada para remover informações pessoais.
7. Alterações locais em configuração.

Nunca envie senha, token, chave privada, conteúdo completo de credenciais ou dumps irrestritos do ambiente.

## 16. Qualidade e suporte

### Estado relatado na conclusão do desenvolvimento

| Verificação | Evidência informada |
|---|---|
| Formatação Bash | shfmt 3.8.0: aprovado em 22 scripts |
| Análise estática Bash | ShellCheck 0.9.0: aprovado em 22 scripts |
| Bats-core | 1.10.0: quatro adaptadores aprovados |
| Verificações unitárias internas | 161 aprovadas |
| Integração developer | 57 verificações aprovadas |
| Integração minimal/server | Seis blocos por perfil aprovados |
| Inspeção /root | 14 caminhos por perfil |
| GitHub Actions remoto | Ainda não executado no último relatório |
| VM/servidor com boot e PAM | Ainda não validado no último relatório |
| Debian/arm64/outras versões | Não anunciar suporte garantido sem testes |
| Licença | Pendente de decisão do responsável na emissão deste manual |

Os números não devem ser somados como se todos representassem casos independentes: os adaptadores Bats executam as mesmas suítes internas.

Esses resultados são de uma revisão relatada. Mudanças futuras em código, templates ou locks exigem nova validação correspondente.

### Executar testes unitários — ambiente de desenvolvimento

Na raiz do repositório, os scripts utilizados no projeto são:

```bash
bash tests/unit/test_phase1_contract.sh
bash tests/unit/test_phase2_state_and_reversibility.sh
bash tests/unit/test_phase3_packages_tools_plugins.sh
bash tests/unit/test_phase4_docker_contract.sh
```

Esses testes foram projetados para sandboxes temporárias. Não defina manualmente TS_TEST_* para contornar falhas em uma instalação real.

A suíte `tests/integration/test_ubuntu2404_container.sh` deve ser executada dentro da imagem Ubuntu prevista, não no host Aurora.

Consulte [`docs/desenvolvimento.md`](desenvolvimento.md) para o ambiente de qualidade; não instale ferramentas no host por copiar um comando destinado a container.

## 17. Checklists

### Antes da instalação

- [ ] Estou no Ubuntu-alvo, ou construindo Docker a partir do host correto.
- [ ] Confirmei o checkout e consultei --help.
- [ ] Escolhi perfil e componentes.
- [ ] Revisei configurações existentes e backups.
- [ ] Executei --dry-run.
- [ ] Não forneci senha/token a arquivo de configuração.
- [ ] Entendi a política de conflitos e a possível troca de shell.

### Depois da instalação

- [ ] Doctor não apresenta erros obrigatórios.
- [ ] Zsh inicia sem mensagens de erro.
- [ ] Ferramentas escolhidas estão disponíveis.
- [ ] Superfile foi experimentado primeiro com dados de teste.
- [ ] Sei onde ficam logs, backups e manifestos.
- [ ] Sei se meu container é descartável ou mantido.

### Antes da restauração

- [ ] Li a ajuda da versão local.
- [ ] Executei a simulação.
- [ ] Confirmei o usuário e o manifesto escolhido.
- [ ] Preservei mudanças locais importantes.
- [ ] Não vou apagar pacotes ou estado manualmente para “forçar”.

## 18. Referências

### Documentação do projeto

- [`README.md`](../README.md)
- [`CHANGELOG.md`](../CHANGELOG.md)
- [`docs/arquitetura.md`](arquitetura.md)
- [`docs/instalacao.md`](instalacao.md)
- [`docs/perfis.md`](perfis.md)
- [`docs/parametros.md`](parametros.md)
- [`docs/docker.md`](docker.md)
- [`docs/superfile.md`](superfile.md)
- [`docs/seguranca.md`](seguranca.md)
- [`docs/backup-restauracao.md`](backup-restauracao.md)
- [`docs/desenvolvimento.md`](desenvolvimento.md)
- [`docs/matriz-de-testes.md`](matriz-de-testes.md)
- [`docs/fontes-e-versoes.md`](fontes-e-versoes.md)
- [`docs/solucao-de-problemas.md`](solucao-de-problemas.md)
- [`tests/README.md`](../tests/README.md)

### Fontes externas oficiais

- Docker run: https://docs.docker.com/reference/cli/docker/container/run/
- Rede none: https://docs.docker.com/engine/network/drivers/none/
- Contexto de build: https://docs.docker.com/build/concepts/context/
- Bind mounts: https://docs.docker.com/engine/storage/bind-mounts/
- Compose: https://docs.docker.com/compose/
- Superfile — tutorial: https://superfile.dev/getting-started/tutorial/
- Superfile — atalhos: https://superfile.dev/list/hotkey-list/
- Superfile — configuração: https://superfile.dev/configure/config-file-path/
- tmux — início: https://github.com/tmux/tmux/wiki/Getting-Started
- Zsh: https://zsh.sourceforge.io/Doc/
- Starship: https://starship.rs/

### Política de revisão deste manual

Atualize este documento sempre que mudar o contrato de parâmetros, perfis, caminhos, mecanismo de backup ou política de suporte. Não copie automaticamente resultados de uma revisão anterior para declarar uma nova versão testada.
