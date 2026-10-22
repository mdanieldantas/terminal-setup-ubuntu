# Contrato de parâmetros e configuração (`terminal-setup`)

Este documento descreve o contrato completo de linha de comando (`install-terminal.sh`) e o formato restrito do arquivo de preferências (`terminal.conf`), conforme implementado na Fase 1 do projeto.

> **Onde executar:** todos os comandos abaixo devem ser executados como **usuário comum** (nunca como `root`). Para apenas inspecionar o plano sem modificar o sistema, adicione `--dry-run`.

---

## 1. Como invocar o instalador

Em partições compartilhadas Windows/Linux (como NTFS com `core.filemode=false`), o bit executável pode não ser preservado pelo sistema de arquivos. Por isso, invoque sempre os scripts explicitamente com `bash`:

```bash
# Usuário comum: exibir ajuda sem tocar no sistema
bash ./install-terminal.sh --help

# Usuário comum: exibir versão sem tocar no sistema
bash ./install-terminal.sh --version

# Usuário comum: planejar instalação do perfil developer sem escrita e sem rede
bash ./install-terminal.sh --profile developer --dry-run
```

O instalador **não** deve ser executado com `source ./install-terminal.sh` nem colado diretamente no terminal.

---

## 2. Parâmetros de linha de comando (`install-terminal.sh`)

| Parâmetro | Valores permitidos | Padrão | Comportamento |
|---|---|---|---|
| `--help`, `-h` | *(sem valor)* | — | Exibe a ajuda em português e encerra com código `0` sem criar diretórios, logs ou arquivos. |
| `--version` | *(sem valor)* | — | Exibe nome e versão do projeto e encerra com código `0` sem efeitos colaterais. |
| `--profile` | `minimal`, `developer`, `server` | `minimal` | Seleciona o perfil base de ferramentas. Incompatível com `--only`. |
| `--dry-run` | *(sem valor)* | desativado | Apenas valida argumentos e exibe o plano completo. **Não** cria diretórios, logs ou backups, **não** acessa a rede, **não** chama `sudo` e **não** executa `chsh`. Prevalece sobre qualquer opção de escrita. |
| `--yes` | *(sem valor)* | desativado | Aceita confirmações interativas de baixo risco cujo padrão já seja positivo (como confirmar o início após ver o plano). **Não** autoriza substituir arquivos conflitantes, ativar `vi-mode`, trocar o shell padrão nem configurar identidade Git. |
| `--non-interactive` | *(sem valor)* | desativado | Proíbe qualquer prompt interativo (`read`, `chsh`, `sudo` com senha). Converte padrões `ask` em equivalentes seguros (`skip`, `keep`, `no`). |
| `--config` | caminho de arquivo | *(nenhum)* | Lê preferências de um arquivo explícito no formato `CHAVE=valor`. Nenhum arquivo de configuração pessoal é lido implicitamente. |
| `--skip-system-packages` | *(sem valor)* | desativado | Valida requisitos, mas não executa APT nem chama `sudo`. |
| `--skip-git` | *(sem valor)* | desativado | Não instala, não configura e não utiliza Git; omite com aviso os plugins Zsh do perfil que dependem de Git. |
| `--git-identity` | `ask`, `skip`, `configure` | `ask` (`skip` em `--non-interactive`) | Define o tratamento de `user.name` e `user.email` globais do Git. |
| `--git-name` | texto não vazio | *(vazio)* | Nome para `user.name` global do Git. Permitido **somente** quando `--git-identity configure`. |
| `--git-email` | e-mail validado | *(vazio)* | E-mail para `user.email` global do Git. Permitido **somente** quando `--git-identity configure`. |
| `--git-defaults` | `ask`, `keep`, `apply` | `ask` (`keep` em `--non-interactive`) | Define se configurações globais recomendadas do Git (como branch padrão e editor) serão aplicadas. |
| `--change-shell` | `ask`, `no`, `yes` | `ask` (`no` em `--non-interactive`) | Define se o shell de login do usuário será alterado para Zsh via `chsh`. `yes` exige confirmação e ambiente interativo. |
| `--include` | lista separada por vírgulas | *(vazio)* | Acrescenta componentes conhecidos ao perfil selecionado. |
| `--exclude` | lista separada por vírgulas | *(vazio)* | Remove componentes opcionais ou não obrigatórios do perfil selecionado. |
| `--only` | lista separada por vírgulas | *(vazio)* | Substitui a seleção do perfil pelos componentes informados e resolve automaticamente suas dependências obrigatórias. |
| `--icons` | `plain`, `nerd` | `plain` | Define o modo visual do Starship (`plain.toml` vs `nerd.toml`) e de atalhos compatíveis. |
| `--vi-mode` | *(sem valor)* | desativado | Habilita conscientemente o plugin opcional `zsh-vi-mode`. |
| `--on-conflict` | `ask`, `keep`, `backup-replace` | `ask` (`keep` em `--non-interactive`) | Política para arquivos de configuração já existentes e divergentes no `HOME`. |

Todas as opções que recebem valor aceitam tanto `--opcao valor` quanto `--opcao=valor`. Valores vazios (`--opcao ""` ou `--opcao=`) são rejeitados.

---

## 3. Catálogo de componentes conhecidos na v1

Os identificadores aceitos em `--include`, `--exclude` e `--only` (e nas chaves `INCLUDE` e `EXCLUDE` de `terminal.conf`) são:

- **Base obrigatória do ambiente:** `zsh`, `nano`, `ca-certificates`, `curl`, `jq` (e `git`, salvo quando `--skip-git` estiver ativo).
- **Ferramentas CLI e TUI:** `starship`, `fzf`, `ripgrep`, `bat`, `fd`, `tmux`, `zoxide`, `eza`, `superfile`, `btop`.
- **Plugins Zsh (gerenciados via Git com commit fixado):** `zsh-autosuggestions`, `zsh-history-substring-search`, `zsh-syntax-highlighting`, `zsh-vi-mode`.

Qualquer nome fora dessa lista é rejeitado com código de saída `2` antes de qualquer efeito colateral.

---

## 4. Regras de precedência

A resolução das opções segue estritamente a ordem:

1. **Valores padrão** internos do instalador (`minimal`, `plain`, `ask`, etc.).
2. **Arquivo indicado explicitamente por `--config <caminho>`** (sobrepõe os padrões).
3. **Parâmetros de linha de comando (CLI)** (sobrepõem tanto os padrões quanto o arquivo `--config`).

Variáveis de ambiente genéricas (como `PROFILE=...` ou `ICONS=...` exportadas no shell) **não** são lidas como opções do projeto na v1. Apenas variáveis operacionais padrão do sistema (`HOME`, `USER`, `PATH`, `TERM`, `NO_COLOR`, `ZDOTDIR`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME`) são consultadas.

---

## 5. Regras de validação e conflitos

O parser valida todos os argumentos antes de qualquer escrita:

1. **Flags desconhecidas, argumentos posicionais ou listas malformadas** (`--include ""`, `--include "eza,,btop"`, espaços dentro da lista CSV): erro imediato (`código 2`).
2. **Exclusividade do `--only`:** `--only` não pode ser combinado com `--profile` explícito (na CLI ou em `PROFILE` do `--config`), nem com `--include`/`--exclude` (`INCLUDE`/`EXCLUDE`).
3. **Inclusão e exclusão simultânea:** informar o mesmo componente em `--include` e `--exclude` é erro (`código 2`).
4. **Proteção de componentes base e dependências:**
   - Excluir um componente base obrigatório (`zsh`, `nano`, `ca-certificates`, `curl`, `jq`) via `--exclude` é erro explicado (`código 2`).
   - Para omitir `git`, deve-se usar `--skip-git` (e não `--exclude git`).
   - Excluir uma dependência obrigatória de outro componente selecionado é erro explicado.
   - No modo `--only`, as dependências obrigatórias dos componentes escolhidos são incluídas automaticamente (por exemplo, `--only superfile` inclui `ca-certificates`, `curl` e `jq`).
5. **Prioridade de `--skip-git`:**
   - Quando `--skip-git` é usado com um perfil (`minimal`, `developer`, `server`), `git` e os plugins Zsh do perfil são omitidos com aviso explícito no plano.
   - Se o usuário exigir explicitamente `git`, `--vi-mode` ou um plugin Zsh em `--include` ou `--only` junto com `--skip-git`, o instalador falha com erro explicado (`código 2`).
   - `--skip-git` é incompatível com `--git-identity configure` e com `--git-defaults apply`.
6. **Diferença entre `--yes` e `--non-interactive`:**
   - `--yes` apenas confirma perguntas operacionais de baixo risco com padrão positivo; mantém intactos os padrões `ask` para identidade Git, defaults Git, troca de shell e conflitos de arquivos, e não ativa `vi-mode`.
   - `--non-interactive` proíbe qualquer leitura interativa: converte padrões `ask` em `GIT_IDENTITY=skip`, `GIT_DEFAULTS=keep`, `CHANGE_SHELL=no` e `ON_CONFLICT=keep`.
   - Passar explicitamente `ask` para qualquer política junto com `--non-interactive` é erro (`código 2`).
   - `--non-interactive --change-shell yes` é erro (`código 2`).
   - `--non-interactive --git-identity configure` exige `--git-name` e `--git-email` completos e válidos (`código 2` se ausentes).

---

## 6. Formato restrito do arquivo `terminal.conf`

Quando informado via `--config <caminho>`, o arquivo é processado por `lib/config-parser.sh` (nunca por `source` ou `eval`):

- Codificação UTF-8, uma definição `CHAVE=valor` por linha (separada no primeiro `=`).
- Linhas em branco e linhas iniciadas por `#` são ignoradas.
- **Chaves permitidas:**
  - `PROFILE` (`minimal` | `developer` | `server`)
  - `ICONS` (`plain` | `nerd`)
  - `GIT_IDENTITY` (`ask` | `skip` | `configure`)
  - `GIT_NAME` (texto sem caracteres de controle ou encadeamento de shell; preserva espaços internos)
  - `GIT_EMAIL` (e-mail sem espaços ou caracteres de controle)
  - `GIT_DEFAULTS` (`ask` | `keep` | `apply`)
  - `CHANGE_SHELL` (`ask` | `no` | `yes`)
  - `ON_CONFLICT` (`ask` | `keep` | `backup-replace`)
  - `VI_MODE` (`true` | `false`)
  - `INCLUDE` (lista CSV de componentes conhecidos)
  - `EXCLUDE` (lista CSV de componentes conhecidos)
- **Rejeições de segurança:**
  - Chaves desconhecidas ou duplicadas;
  - Presença de byte `NUL` (`\0`) ou caracteres de controle;
  - Aspas de shell envolvendo o valor (`"..."` ou `'...'`);
  - Sintaxe de expansão ou substituição de comando (`$(...)`, `` `...` ``, `${...}`).

Consulte `examples/terminal.conf.example` para um modelo comentado.

---

## 7. Códigos de saída

| Código | Constante interna | Significado |
|---|---|---|
| `0` | `TS_EXIT_OK` | Sucesso (`--help`, `--version`, `--dry-run` ou execução concluída). |
| `1` | `TS_EXIT_ERR` | Erro operacional ou requisito de ambiente ausente (ex.: `jq` ausente com `--skip-system-packages`). |
| `2` | `TS_EXIT_USAGE` | Uso inválido de parâmetros, conflito de opções ou erro de sintaxe/validação em `--config`. |
| `3` | `TS_EXIT_PLATFORM` | Plataforma não suportada para execução efetiva (fora de Ubuntu 24.04 LTS `amd64`). |
| `4` | `TS_EXIT_PRIVILEGE` | Execução indevida como `root` (`UID 0`) no instalador de usuário. |
| `5` | `TS_EXIT_NOT_IMPLEMENTED` | Operação de escrita/instalação ainda bloqueada no estágio atual do projeto (Fase 1). |

