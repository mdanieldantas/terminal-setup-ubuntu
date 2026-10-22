# Guia de implementação — Terminal Setup para Ubuntu

- Versão do guia: 1.0
- Data de revisão: 2026-10-22
- Idioma: português do Brasil
- Público: IA de desenvolvimento assistida por um responsável humano
- Natureza: especificação de projeto; não é um script executável nem o prompt inicial da IA
- Nome provisório do projeto: `terminal-setup`

## 1. Objetivo e princípio de trabalho

Criar um projeto Bash modular para instalar ferramentas de terminal e configurar o ambiente de um usuário em Ubuntu, com duas entradas distintas: instalação interativa em servidor/VM/WSL e construção não interativa de uma imagem Docker de desenvolvimento.

O resultado deve ser legível, versionável, testável e conservador com configurações existentes. Não transformar o projeto em um instalador universal de distribuições ou em ferramenta de hardening na primeira versão.

Este guia é o contrato de comportamento. Exemplos de comandos e nomes de funções são propostas de interface a implementar, não garantias de que o código atual já os suporta. Não executar comandos de instalação no computador do responsável sem autorização. Desenvolvimento no Aurora não autoriza usar APT no host.

### Entregas esperadas

1. Repositório completo com scripts, configurações, documentação e testes.
2. Instalador interativo para usuário comum.
3. Fluxos separados para pacotes do sistema e configurações do usuário.
4. Imagem Docker que inicia como usuário comum e não exige senha no build.
5. Diagnóstico, backups e restauração segura de configurações.
6. Relatório de verificações realizadas, limitações e itens não testados.

Não declarar “pronto para produção”, “seguro” ou “testado” sem evidências correspondentes.

## 2. Correções obrigatórias em relação às propostas iniciais

- `--yes` não é um modo não interativo: aceitar confirmações não elimina perguntas por nome/e-mail. Implementar `--non-interactive` separadamente.
- Não executar o instalador de usuário como root para depois trocar para `USER dev`: isso configuraria `/root`, não `/home/dev`.
- Não resolver o build concedendo `NOPASSWD:ALL`. Instalar pacotes como root durante o build e configurar o perfil depois de trocar para o usuário comum.
- `SHELL` no Dockerfile define o interpretador de instruções shell do build; não substitui `CMD`. O container deve ter `CMD` explícito para iniciar Zsh.
- `.dockerignore` deve estar na raiz do contexto de build, ou seguir o nome especial associado ao Dockerfile. A v1 usará a raiz do projeto.
- Um `--dry-run` que cria logs, diretórios ou backups não é livre de alterações. Nesta especificação, ele não escreve no sistema de arquivos e não executa chamadas de rede.
- `zsh -n arquivo1 arquivo2` não deve ser usado como prova de validação de todos os arquivos: validar cada arquivo individualmente.
- Baixar um instalador antes de executá-lo melhora inspeção, mas não prova integridade ou autenticidade. Verificar artefatos e origem conforme a seção de versões.
- Não usar `source terminal.env` em arquivo de configuração arbitrário: isso executa código. Usar parser restrito de pares chave/valor.
- Não substituir `cat`, `ls`, `grep`, `find`, `rm` ou `cd` silenciosamente. Criar atalhos opcionais e preservar ferramentas tradicionais.
- Não incluir SSH, firewall, Fail2ban ou reinicializações automáticas no mesmo fluxo de personalização de terminal.
- Senhas não são parâmetros deste projeto; Git user.name/user.email não são credenciais de autenticação, embora possam ser dados pessoais.

## 3. Escopo e suporte

### 3.1 Plataforma inicial

- Suporte garantido inicial: Ubuntu 24.04 LTS, arquitetura amd64.
- Ubuntu arm64: somente declarar suporte após verificar artefatos de todas as ferramentas e executar testes aplicáveis.
- Outras versões do Ubuntu: futuras extensões com matriz explícita de testes.
- Debian: fora do suporte garantido da v1; não anunciar compatibilidade só porque também utiliza APT.
- Aurora/Fedora: ambiente de desenvolvimento possível, mas host fora do destino de instalação.
- WSL: configuração de terminal possível; não supor systemd, daemon Docker ou serviços ativos.
- Container Ubuntu: adequado para testar pacotes e ambiente de usuário; não equivale a testar boot, SSH e serviços de uma VM.

Não atualizar a distribuição nem executar `apt-get upgrade`, `dist-upgrade` ou reboot automaticamente.

### 3.2 Dois produtos diferentes

1. Ambiente de terminal para usuário em máquina Ubuntu.
2. Imagem de trabalho/desenvolvimento interativo baseada em Ubuntu.

A imagem NÃO é uma imagem mínima para hospedar aplicações de produção. Editores, TUI e plugins fazem sentido para trabalho humano, mas não devem ser colocados automaticamente em imagens de serviços.

### 3.3 Fora do escopo da v1

- Configurar SSH/UFW/Fail2ban/unattended-upgrades.
- Criar usuários ou alterar sudoers em servidores existentes.
- Armazenar senha, token, chave privada ou credencial de nuvem.
- Instalar Docker Engine, Podman, bancos de dados ou servidores web.
- Montar socket Docker, diretórios do host ou dispositivos automaticamente.
- Acessar serviços externos com credenciais.
- Remover pacotes APT na desinstalação.
- Adotar Ansible, Kubernetes, interface web ou gerenciador universal de pacotes.

Documentar hardening como projeto futuro separado, com plano específico contra bloqueio de acesso remoto.

## 4. Arquitetura de privilégios

Separar responsabilidades; não criar `--allow-root` genérico no instalador principal.

### Fluxo A — instalação humana

1. Usuário comum executa `install-terminal.sh`.
2. Preflight valida plataforma, argumentos e dependências antes de escrever arquivos.
3. Planejamento apresenta pacotes, fontes externas, arquivos e backups previstos.
4. Instalação de pacotes delega ao helper administrativo via `sudo` quando necessário.
5. Configuração de Zsh, Git, plugins e ferramentas de usuário ocorre sem sudo, no HOME do usuário efetivo.
6. Troca de shell é opcional e requer consentimento específico.

Se faltar sudo, explicar a alternativa: administrador executa o helper de pacotes; depois o usuário executa `--skip-system-packages`.

### Fluxo B — Docker

1. Build como root instala pacotes e cria usuário `dev`, sem senha e sem sudo irrestrito.
2. Definir HOME, WORKDIR e propriedade dos arquivos de forma explícita.
3. Trocar para `USER dev`.
4. Executar instalador com `--non-interactive --skip-system-packages --git-identity skip --change-shell no` e perfil explícito.
5. Usar `CMD ["/usr/bin/zsh", "-l"]`, validando o caminho real na imagem.

O helper administrativo deve recusar execução sem UID 0 e operar somente sobre pacotes listados. Ele não escreve no HOME do usuário, não configura Git e não executa instaladores remotos genéricos.

## 5. Estrutura do repositório

```text
terminal-setup/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── .editorconfig
├── .gitattributes
├── .gitignore
├── .dockerignore
├── install-terminal.sh
├── doctor.sh
├── uninstall-terminal.sh
├── scripts/
│   └── install-system-packages.sh
├── lib/
│   ├── common.sh
│   ├── arguments.sh
│   ├── platform.sh
│   ├── config-parser.sh
│   ├── plan.sh
│   ├── packages.sh
│   ├── downloads.sh
│   ├── tools.sh
│   ├── plugins.sh
│   ├── backups.sh
│   ├── manifest.sh
│   ├── user-config.sh
│   └── git-config.sh
├── config/
│   ├── zsh/
│   │   ├── zshenv.template
│   │   ├── zshrc
│   │   ├── aliases.zsh
│   │   ├── bindings.zsh
│   │   ├── containers.zsh
│   │   ├── database.zsh
│   │   ├── fzf.zsh
│   │   ├── git.zsh
│   │   ├── plugins.zsh
│   │   └── prompt.zsh
│   │   # Nota: na instalacao em ${XDG_CONFIG_HOME}/terminal-setup/zsh/,
│   │   # tambem e gerado de forma deterministica o arquivo options.zsh
│   │   # (contendo TS_ICONS_MODE e TS_VI_MODE_ENABLED), registrado no
│   │   # manifesto e sujeito as mesmas regras de conflito, backup,
│   │   # idempotencia, validacao 'zsh -n' e restauracao.
│   ├── starship/
│   │   ├── plain.toml
│   │   └── nerd.toml
│   ├── tmux/
│   │   └── tmux.conf
│   └── superfile/
│       └── README.md
├── profiles/
│   ├── minimal.conf
│   ├── developer.conf
│   └── server.conf
├── versions/
│   ├── tools.lock.json
│   └── plugins.lock.json
├── examples/
│   └── terminal.conf.example
├── docker/
│   ├── Dockerfile
│   └── compose.yaml
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── fixtures/
│   └── README.md
├── docs/
│   ├── arquitetura.md
│   ├── parametros.md
│   ├── instalacao.md
│   ├── perfis.md
│   ├── docker.md
│   ├── superfile.md
│   ├── seguranca.md
│   ├── backup-restauracao.md
│   ├── desenvolvimento.md
│   ├── matriz-de-testes.md
│   ├── fontes-e-versoes.md
│   └── solucao-de-problemas.md
└── .github/workflows/
    └── ci.yaml
```

Arquivos de biblioteca são carregados como código confiável do próprio repositório. Arquivos de preferências e perfis são dados, não scripts executados por `source`.

Pode ajustar nomes de módulos quando simplificar de verdade, mas justificar mudanças. Não criar dezenas de arquivos vazios apenas para cumprir a árvore.

## 6. Perfis e ferramentas

Os perfis são conjuntos de ferramentas, não níveis de segurança.

| Componente | minimal | developer | server |
|---|---|---|---|
| Zsh, Git, Nano, CA certificates, curl, jq | sim | sim | sim |
| Starship em modo texto | sim | sim | sim |
| fzf, ripgrep, bat | sim | sim | sim |
| fd, tmux, zoxide | não | sim | sim |
| eza | não | sim | opcional |
| Superfile (`spf`) | não | sim | opcional |
| btop | não | opcional | sim |
| autosuggestions e history-substring-search | não | sim | sim |
| zsh-syntax-highlighting | não | sim | opcional |
| zsh-vi-mode | opcional | opcional | opcional |
| lazygit, delta, restic, rclone | fora da v1 | futuro | futuro |

Decisões consolidadas na revisão da Etapa 0 (2026-10-22):

- **P1 (`eza` e `zoxide`):** utilizar os pacotes APT do Ubuntu 24.04 (`universe`). Manter `versions/tools.lock.json` destinado às ferramentas externas ausentes no APT (`starship` e `superfile`). Documentar as versões APT como versões observadas na distribuição, não como ambiente integralmente congelado.
- **P2 (Plugins Zsh):** gerenciar todos os plugins (`zsh-autosuggestions`, `zsh-history-substring-search`, `zsh-syntax-highlighting` e o opcional `zsh-vi-mode`) via Git no diretório do usuário, com commits fixados em `versions/plugins.lock.json`, respeitando `--skip-git` e sem atualizar plugins ao abrir o shell. Adotar `zsh-syntax-highlighting` (e não `fast-syntax-highlighting`, nunca instalando ambos). `zsh-vi-mode` permanece opcional e desativado por padrão.
- **P3 (`jq` na base):** incluir `jq` como dependência base em todos os perfis, inclusive `minimal`. Utilizar `jq` para leitura e geração de JSON (locks, manifestos e saída `--json`), sem implementar parser ou gerador JSON artesanal com `grep`, `sed` ou concatenação de strings. As operações `--help`, `--version`, validação inicial de argumentos e `--dry-run` devem funcionar sem depender da instalação prévia de `jq`; quando uma operação efetiva precisar de `jq` e ele estiver ausente, informar o requisito claramente.

Dependências auxiliares de download/descompactação só devem entrar quando necessárias ao método escolhido. Não instalar wget, gpg, compiladores e unzip por inércia.

`server` não altera serviços. Superfile deve poder ser incluído explicitamente nesse perfil. Nunca pressupor que uma ferramenta TUI é incompatível com servidores apenas por ser visual.

No Ubuntu, verificar o mapeamento entre pacote e comando, incluindo `fd-find`/`fdfind` e `bat`/`batcat`. Links em `~/.local/bin` só podem ser criados quando não sobrescrevem arquivos ou links preexistentes; registrar propriedade no manifesto.

## 7. Contrato de parâmetros

### 7.1 Instalador principal

| Parâmetro | Valores/padrão | Comportamento |
|---|---|---|
| `--help`, `-h` | sem valor | ajuda sem alterações |
| `--version` | sem valor | versão do projeto sem alterações |
| `--profile` | minimal/developer/server; padrão minimal | seleciona perfil |
| `--dry-run` | desativado | só planeja, sem escrita, rede, sudo ou instalações |
| `--yes` | desativado | aceita confirmações de baixo risco com padrão positivo |
| `--non-interactive` | desativado | proíbe qualquer prompt/read/chsh interativo |
| `--config` | caminho explícito | lê configuração restrita; nenhum arquivo pessoal carregado implicitamente |
| `--skip-system-packages` | desativado | valida requisitos, mas não chama APT/sudo |
| `--skip-git` | desativado | não instala, configura ou usa Git; não clona plugins |
| `--git-identity` | ask/skip/configure; padrão ask | decide tratamento de nome/e-mail |
| `--git-name` | texto não vazio | usado somente com configure |
| `--git-email` | texto validado | usado somente com configure |
| `--git-defaults` | ask/keep/apply; padrão ask | branch/editor globais são opt-in |
| `--change-shell` | ask/no/yes; padrão ask | yes exige confirmação específica e ambiente interativo |
| `--include` | lista separada por vírgula | acrescenta componentes conhecidos |
| `--exclude` | lista separada por vírgula | exclui componentes opcionais |
| `--only` | lista de componentes | substitui seleção do perfil e resolve dependências |
| `--icons` | plain/nerd; padrão plain | modo visual do Starship e aliases |
| `--vi-mode` | desativado | habilita plugin opcional conscientemente |
| `--on-conflict` | ask/keep/backup-replace; padrão ask | política de arquivos existentes |

Regras de validação:

- Rejeitar flags desconhecidas, valores ausentes, listas vazias e componentes desconhecidos antes de efeitos colaterais.
- `--only` é incompatível com perfil explicitamente informado e com include/exclude.
- Incluir e excluir o mesmo componente é erro; não resolver silenciosamente.
- Excluir dependência obrigatória de componente selecionado é erro explicado.
- `--skip-git` tem prioridade: plugins dependentes de Git são omitidos com aviso, ou erro se explicitamente exigidos.
- Em non-interactive: ask vira skip para identidade, keep para defaults Git, no para troca de shell e keep para conflitos.
- `--non-interactive --git-identity configure` exige nome/e-mail completos; não pedir dados ausentes.
- `--non-interactive --change-shell yes` é erro; Docker define o shell na criação do usuário e em CMD.
- `--yes` não autoriza substituir arquivos, ativar vi-mode, trocar shell ou definir identidade pessoal.
- `--dry-run` prevalece sobre todas as opções de escrita.
- Non-interactive não pode travar esperando senha de sudo: validar credencial disponível com sudo não interativo, ou solicitar helper root separado.
- Não anunciar atualizações automáticas de ferramentas: uma atualização de lock é mudança explícita revisada.

### 7.2 Preferências em arquivo

Usar `terminal.conf`, formato simples `CHAVE=valor`, uma chave por linha, UTF-8. Permitir comentários iniciados por `#` em linha própria e linhas vazias. Separar no primeiro `=`. Preservar espaços do valor conforme regra documentada; não fazer expansão de shell, substituição de comando, escapes, interpolação ou parsing YAML improvisado.

Chaves permitidas: PROFILE, ICONS, GIT_IDENTITY, GIT_NAME, GIT_EMAIL, GIT_DEFAULTS, CHANGE_SHELL, ON_CONFLICT, VI_MODE, INCLUDE, EXCLUDE.

Rejeitar chaves desconhecidas/duplicadas, NUL e valores inválidos. Não permitir que o arquivo defina diretórios de sistema ou comandos. Precedência: defaults < arquivo explicitamente indicado < CLI. Não ler variáveis genéricas do ambiente como opções do projeto na v1; HOME/XDG/PATH continuam sendo ambiente operacional.

Não colocar senhas no arquivo. Incluir `terminal.conf` local no gitignore/dockerignore e manter o exemplo versionado. Explicar que .gitignore não apaga dados já commitados e que um arquivo local não é um cofre de segredos.

### 7.3 Parâmetros auxiliares

- `doctor.sh`: --help, --profile, --json, --strict. Somente leitura, sem sudo ou rede; não reparar automaticamente.
- `uninstall-terminal.sh`: --help, --dry-run, --non-interactive, --restore INSTALL_ID, --on-modified keep. Não remover pacotes na v1.
- Helper de pacotes: --help, --profile e seleção validada de componentes. Nunca aceitar fragmentos de shell como pacote ou comando.
- Docker: argumentos não sensíveis DEV_USER, DEV_UID, DEV_GID e PROFILE, com validação e suporte inicial documentado. Sem senha, token, nome/e-mail Git em ARG/ENV.

## 8. Estado, logs, backups e idempotência

Usar diretórios do usuário, não gravar logs no checkout do projeto:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/terminal-setup/
${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/
├── logs/
├── backups/<install-id>/
└── manifests/<install-id>.json
```

- Criar identificador de execução resistente a colisão.
- Aplicar umask 077 aos arquivos privados de estado.
- Manifesto registra caminho, tipo, estado anterior (inclusive ausente ou symlink), backup, checksum instalado, versão e resultado da operação.
- Não restaurar manifesto como shell nem confiar cegamente em caminhos nele: validar propriedade, diretórios permitidos e traversal.
- Fazer backup antes de substituir e escrever por temporário no mesmo diretório + rename quando aplicável.
- Para symlinks, preservar o próprio link e seu destino textual; não seguir um symlink e sobrescrever o alvo inadvertidamente.
- Segunda execução com conteúdo idêntico não sobrescreve nem produz backups redundantes.
- Não sobrescrever arquivo local divergente sem política explícita.
- Se houver falha parcial, registrar o que mudou; não prometer transação completa de APT.
- Logs não exibem e-mail Git, tokens, senhas nem ambiente completo. Não usar set -x.
- `--dry-run`, --help, --version e doctor não criam nem logs.
- Evitar que duas instalações concorrentes modifiquem os mesmos arquivos; usar lock de execução somente em execução efetiva.

## 9. Download, versões e plugins

Manter locks JSON com schema documentado para ferramenta, versão, arquitetura, URL oficial, checksum e data de verificação. Plugins devem apontar para commit específico; registrar origem e licença quando relevante.

Preferência:

1. APT da versão Ubuntu suportada, quando atende ao recurso necessário.
2. Artefato oficial versionado e checksum verificado para binários externos.
3. Instalador oficial apenas quando necessário, após revisão do seu comportamento e das opções efetivamente disponíveis.

Não inventar checksums, URLs, flags de prefixo ou versões. Consultar a documentação oficial e releases durante a implementação. Se uma ferramenta obrigatória não puder ser verificada, reportar bloqueio e não publicar uma implementação falsa. Ferramenta opcional pode ficar indisponível explicitamente, sem simular sucesso.

Regras:

- HTTPS, falha em HTTP de erro, timeouts e tentativas limitadas.
- Validar arquitetura e correspondência do artefato antes de instalar.
- Downloads para diretório temporário seguro, limpo em sucesso/falha.
- Não executar conteúdo remoto com sudo como consequência implícita de personalização.
- Instalar binários do usuário em ~/.local/bin ou diretório versionado sob ~/.local/share/terminal-setup com link controlado.
- Usar ~/.local/bin no PATH antes de verificar ferramentas recém-instaladas.
- Validar comando e versão após instalar.
- Não usar latest como lock reproduzível.
- Pacotes APT e tags de imagem podem mudar: fixar ferramentas externas não torna o ambiente inteiro bit a bit reproduzível. Documentar limites, digest de base quando usado e estratégia de atualização.
- Checksum baixado junto do artefato ajuda contra corrupção; não é autenticação independente contra comprometimento da mesma origem.

Plugins: sem git pull no início do shell e sem atualização de rede ao abrir terminal. Selecionar combinação e ordem de carga compatíveis após ler documentação upstream. Configurar zsh-vi-mode antes de sua inicialização quando o plugin exigir. Não ativá-lo por padrão.

## 10. Configuração Zsh, Starship, tmux e Superfile

- Entradas Bash executáveis usam shebang, strict mode e trap que preserva status de erro. Não depender de strict mode como única validação.
- Executar como arquivo (`bash ./install-terminal.sh`); não orientar colar o corpo inteiro ou sourcear o instalador.
- Resolver diretório do script a partir do arquivo real e validar diretórios antes de qualquer escrita.
- Não alterar IFS global sem necessidade; delimitação explícita em loops.
- Não usar eval para construir comandos. Integrações oficiais como eval de `starship init zsh` são exceções delimitadas e explicadas.
- Não fazer chamadas Docker/Podman/rede custosas no startup apenas para detectar recursos opcionais.
- Definir fallback claro se ferramentas ou módulos estiverem ausentes.
- Zsh interativo deve iniciar sem erros com HOME vazio e com ambiente já configurado.
- Comandos não interativos não devem receber banners, cores ou texto extra pelo stdout.
- Não quebrar ZDOTDIR existente. Se houver valor customizado, preservar ou parar com instrução explícita; não redirecionar silenciosamente.
- Preservar configurações pré-existentes de ~/.zshenv e ~/.zshrc. Para conflitos, política keep é segura; explicar se isso impede ativação automática. Integração por bloco gerenciado só se bem delimitada e testada, nunca anexar duplicatas.
- Documentar quais arquivos são do projeto e quais permanecem do usuário.
- Histórico com permissões privadas; não prometer que HIST_IGNORE_SPACE protege segredos em geral.
- Starship padrão sem símbolos dependentes de fonte especial. Modo nerd opcional.
- Nerd Font é instalada/configurada no terminal cliente (por exemplo, Konsole no Aurora), não no servidor SSH para consertar renderização local.
- tmux sem baixar plugins ou executar comandos externos pesados ao iniciar; configuração simples.
- Superfile é iniciado com `spf`; usar documentação oficial atual de instalação, configuração e tutorial.
- Não criar config.toml fictício para Superfile. Se defaults upstream bastarem, manter apenas documentação até verificar schema e compatibilidade da versão fixada.
- Aliases de Docker/bancos apenas quando o comando existir; não instalar serviços por causa deles. Funções validam argumentos.

## 11. Git e dados pessoais

- Manter perguntas interativas: isso já é uma característica correta do script original.
- Instalar Git não significa alterar a identidade global.
- Preservar identidade e defaults atuais até consentimento específico.
- Nunca instalar senha Git, token de GitHub, credential helper inseguro ou chave SSH privada.
- Validação de e-mail deve evitar espaços/quebras de linha e erros óbvios, sem alegar validação completa de RFC.
- `--skip-git` significa não usar Git nem para plugins; mostrar consequência.
- Identidade não deve ser gravada em lock, manifesto, imagem, logs ou arquivos de exemplo reais.
- Documentar que configuração global Git reside no perfil do usuário e não configura automaticamente o Git do host a partir de um container isolado.

## 12. Docker e Compose

- Contexto de build: raiz do repositório.
- Comando de referência: `docker build -f docker/Dockerfile -t terminal-setup:dev .`.
- Base inicial ubuntu:24.04; registrar digest validado se utilizado, sem inventá-lo.
- Combinar update/install no mesmo RUN, usar --no-install-recommends e remover listas APT da camada final de instalação.
- Dependências administrativas apenas no estágio apropriado; não instalar sudo só para contornar desenho incorreto.
- A criação do usuário valida colisões de UID/GID e nomes existentes na base; não supor UID 1000 livre.
- Instalar pacotes como root, copiar fontes com ownership correto e configurar como dev.
- Evitar `chsh` e prompts no build; definir shell no useradd e CMD.
- `USER dev`, WORKDIR e HOME coerentes; CMD inicia Zsh.
- Compose moderno sem campo top-level version legado; build.context `..` quando o compose fica em docker/ e dockerfile relativo ao contexto.
- stdin_open e tty para uso interativo; sem privileged, host network ou socket Docker.
- Volumes do host são opt-in e documentados; não montar automaticamente /home, /root ou o HOME do usuário do Aurora.
- `.dockerignore` na raiz exclui .git, dados locais, logs, backups e segredos, sem excluir exemplos necessários por engano.
- Imagem não contém identidade pessoal nem chaves privadas.
- Não recomendar docker commit como método principal de entrega; manter Dockerfile e locks versionados.
- Explicar diferença entre shell de login e shell interativo, e que `docker exec ... bash` abre Bash mesmo que o shell de login do usuário seja Zsh.

## 13. Doctor, desinstalação e restauração

Doctor verifica:

- Plataforma/arquitetura, usuário, HOME e caminhos XDG.
- Comandos, versões e mapeamentos Ubuntu.
- Presença e sintaxe de cada arquivo, individualmente.
- PATH, links gerenciados e disponibilidade dos binários.
- Shell registrado e shell atual como fatos separados; SHELL sozinho não prova o processo atual.
- Plugins e commits selecionados.
- Manifesto mais recente e integridade de arquivos gerenciados.
- Ferramentas ausentes opcionais como aviso; requeridas como erro.

Saída humana em PT-BR e JSON limpo quando --json. Definir códigos estáveis: 0 sem erros obrigatórios; 1 requisito ou integridade falhou; 2 uso inválido. --strict pode converter avisos em falha, conforme documentação.

Desinstalação:

- Opera exclusivamente em recursos registrados no manifesto e em destinos permitidos.
- Preserva qualquer arquivo modificado depois da instalação, informando conflito.
- Restaura backups somente quando o estado atual corresponde ao esperado e o usuário autorizou restauração.
- Não apaga diretórios inteiros por serem “do projeto” se houver conteúdo desconhecido.
- Não remove Git, Zsh, APT, histórico pessoal, credenciais ou todos os plugins de forma indiscriminada.
- Preserva backups por padrão e permite executar a restauração duas vezes sem danos.
- Não remove Zsh enquanto ele ainda for shell padrão; apenas orienta o usuário.

## 14. Segurança e ergonomia

- Interfaces em português; nomes técnicos, comandos e chaves permanecem em formato convencional.
- Cada comando da documentação explica o que faz e onde executar: host, root do container ou usuário comum.
- Não usar senhas fracas de exemplo e não pedir senha pelo read do script; autenticação administrativa fica a cargo de sudo/chsh.
- Não usar cores como única forma de comunicar status; suporte a NO_COLOR.
- Não depender de emojis para entender erros.
- Entrada inválida deve produzir erro útil e não executar texto recebido.
- Prevenir injeção por listas de pacotes, URLs, nomes de componentes e valores de config.
- Arquivos de configuração do usuário não são confiáveis como código privilegiado.
- Uso em repositório compartilhado Windows/Linux: normalizar LF, UTF-8 e execução com bash quando bit executável não estiver preservado; não aplicar chmod recursivo no host.

## 15. Testes e integração contínua

Ferramentas sugeridas: ShellCheck para análise estática, shfmt para formatação e Bats-core para testes comportamentais. Verificar versões/instalação nas fontes oficiais.

### Testes obrigatórios

1. Parser: flags válidas/inválidas, conflitos, precedência e dados maliciosos em terminal.conf não executados.
2. Help/version em ambiente somente leitura, sem mkdir/log/sudo.
3. Dry-run com mocks de comandos administrativos e snapshot antes/depois; nenhuma escrita ou rede.
4. Non-interactive com stdin fechado e timeout: não trava nem pede senha.
5. --yes não altera identidade nem shell nem sobrescreve conflitos.
6. Instalação limpa em Ubuntu suportado.
7. Segunda instalação idempotente.
8. Configuração existente, ZDOTDIR customizado, espaços em caminhos e symlinks.
9. Backup/restore e recusa de remoção de arquivo posteriormente editado.
10. Downloads com falha, checksum incorreto e arquitetura não suportada.
11. Git ausente/skip-git e plugins dependentes.
12. `bash -n` em cada script Bash e `zsh -n` em cada arquivo Zsh separadamente.
13. Shell interativo de smoke test sem mensagens de erro e sem chamadas de rede.
14. Docker build sem stdin/senha e execução final com UID diferente de 0.
15. Isolamento: arquivos do usuário dev não ficam apenas em /root.
16. Verificar que segredos e terminal.conf locais não entram no contexto/camadas da imagem.
17. Manifesto malformado/com traversal não consegue remover arquivos externos.
18. Falha de uma instalação não remove arquivos anteriores nem mascara o status de saída.

A CI executa testes sem permissão para modificar máquinas reais. Testes privilegiados limitados a containers descartáveis. Testes de boot/SSH só em VM separada, caso sejam adicionados no futuro.

Fixar dependências de CI adequadamente e documentar atualização. Não colocar credenciais ou sudo irrestrito desnecessário nos testes.

## 16. Etapas de implementação e portões de revisão

### Etapa 0 — levantamento

- Ler o script existente quando fornecido e comparar com este guia.
- Verificar documentação oficial de cada ferramenta escolhida e métodos de instalação disponíveis.
- Registrar versões, URLs, checksums e limites reais em docs/fontes-e-versoes.md.
- Não executar o script antigo no host para “ver o que acontece”.

### Etapa 1 — contrato e planejamento

- Implementar parser, perfis, configuração restrita e preflight.
- Escrever testes de help, dry-run, prompts e argumentos antes de instalar ferramentas.
- Aprovação: planejamento sem efeito colateral e interface documentada.

### Etapa 2 — configuração e reversibilidade

- Implementar manifesto, backup, conflitos, configuração e restore.
- Testar em HOME temporário.
- Aprovação: idempotência e preservação de conteúdo desconhecido comprovadas.

### Etapa 3 — pacotes e ferramentas

- Implementar helper APT e instaladores de usuário verificados.
- Adicionar Superfile e plugins sem aliases invasivos.
- Aprovação: instalação limpa e falhas de download cobertas.

### Etapa 4 — Docker

- Criar Dockerfile/Compose sem sudo irrestrito, prompt ou identidade pessoal.
- Aprovação: build completo e Zsh funcionando como dev.

### Etapa 5 — documentação e CI

- Completar README, exemplos e matriz de testes.
- Aprovação: nenhuma promessa de compatibilidade sem teste e nenhum TODO oculto em caminho anunciado como funcional.

Não implementar hardening ou expansão de plataformas no meio dessas etapas sem revisão de escopo.

## 17. Exemplos de interface a implementar

```bash
# Usuário comum no Ubuntu: ver plano sem modificar nada.
bash ./install-terminal.sh --profile developer --dry-run

# Usuário comum: instalação interativa com preservação por padrão.
bash ./install-terminal.sh --profile developer

# Usuário comum: servidor com ferramentas extras, sem alterar serviços.
bash ./install-terminal.sh --profile server --include superfile

# Usuário comum: somente Superfile e suas dependências necessárias.
bash ./install-terminal.sh --only superfile

# Usuário comum: diagnóstico somente leitura.
bash ./doctor.sh --profile server

# Raiz do projeto no host com Docker: construir imagem de trabalho.
docker build -f docker/Dockerfile -t terminal-setup:dev .

# Host: iniciar ambiente descartável, sem volume nem socket Docker.
docker run --rm -it terminal-setup:dev

# Host: usar o Compose localizado na subpasta docker.
docker compose -f docker/compose.yaml run --rm terminal
```

Não copiar essas interfaces para o README antes de implementá-las e testá-las. O nome de serviço Compose deve ser terminal para corresponder ao exemplo.

## 18. Critérios finais de aceitação

- [ ] Nenhum comando do projeto altera APT no Aurora host.
- [ ] Instalador principal recusa root sem modificar arquivos.
- [ ] Helper root não configura HOME nem identidade.
- [ ] Docker configura dev após USER dev e inicia como usuário não root.
- [ ] Não há NOPASSWD:ALL, privileged ou socket Docker no padrão.
- [ ] Dry-run é sem escrita e sem rede.
- [ ] Non-interactive não contém perguntas escondidas.
- [ ] --yes mantém decisões pessoais e destrutivas fora da aprovação genérica.
- [ ] Config existente e symlinks são preservados ou substituídos com consentimento/backup.
- [ ] Superfile funciona por spf; configurações não foram inventadas.
- [ ] Vi-mode é opcional; fonte Nerd não é imposta no servidor.
- [ ] Cada script/config foi validado de modo apropriado.
- [ ] Segunda execução não produz mudanças desnecessárias.
- [ ] Desinstalação não remove pacotes ou arquivos desconhecidos.
- [ ] Lock externo contém somente dados verificados, sem latest ou checksum fictício.
- [ ] Logs não vazam identidade Git nem credenciais.
- [ ] Documentação distingue testado, previsto e não suportado.
- [ ] Relatório final identifica testes executados, falhas, limitações e próximos passos.

## 19. Fontes oficiais para verificação

As fontes abaixo devem ser revisitadas na implementação. Este guia não congela o conteúdo futuro delas; registrar data de consulta e detalhes efetivamente usados.

- Ubuntu Server: https://documentation.ubuntu.com/server/
- Dockerfile (USER, CMD, SHELL): https://docs.docker.com/reference/dockerfile/
- Contexto e .dockerignore: https://docs.docker.com/build/concepts/context/
- Boas práticas de build: https://docs.docker.com/build/building/best-practices/
- Compose: https://docs.docker.com/compose/
- GNU Bash: https://www.gnu.org/software/bash/manual/
- Zsh: https://zsh.sourceforge.io/Doc/
- Starship: https://starship.rs/
- zoxide: https://github.com/ajeetdsouza/zoxide
- Superfile: https://superfile.dev/
- Tutorial Superfile: https://superfile.dev/getting-started/tutorial/
- Caminhos Superfile: https://superfile.dev/configure/config-file-path/
- Fontes/renderização Superfile: https://superfile.dev/troubleshooting/
- fzf: https://github.com/junegunn/fzf
- eza: https://github.com/eza-community/eza
- bat: https://github.com/sharkdp/bat
- fd: https://github.com/sharkdp/fd
- ripgrep: https://github.com/BurntSushi/ripgrep
- tmux: https://github.com/tmux/tmux
- jq: https://jqlang.org/
- btop: https://github.com/aristocratos/btop
- Plugins: repositórios oficiais de cada plugin selecionado; confirmar proprietário, documentação, commit e licença.
- ShellCheck: https://www.shellcheck.net/
- shfmt: https://github.com/mvdan/sh
- Bats-core: https://bats-core.readthedocs.io/

A licença MIT é uma proposta para o código original: responsável deve confirmar autoria/titularidade antes de preencher LICENSE. Dependências mantêm suas próprias licenças.

## 20. Regra de entrega da IA

Entregar arquivos reais, não apenas uma árvore ou exemplos de pseudocódigo. Não preencher versões, checksums ou resultados de teste por adivinhação. Se houver impedimento de consulta/execução, explicar o impedimento e separar claramente o que foi implementado do que ainda não foi validado.

Antes de executar comandos com efeitos externos, apresentar o plano e respeitar as permissões do ambiente e as aprovações do responsável. A criação dos arquivos do projeto não equivale a autorização para instalar ferramentas, alterar o host, publicar repositório ou acessar servidores reais.
