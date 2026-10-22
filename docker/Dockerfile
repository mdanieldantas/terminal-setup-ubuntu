# ==============================================================================
# docker/Dockerfile — Ambiente Ubuntu 24.04 LTS (amd64) do terminal-setup
#
# Regras aplicadas (Secoes 12, 14, 15 e 18 do guia):
#   - Contexto de build: raiz do repositorio
#     (docker build -f docker/Dockerfile -t terminal-setup:dev .)
#   - Base inicial: ubuntu:24.04 (sem inventar digest nao verificado)
#   - Pacotes APT instalados como root via helper administrativo do projeto no
#     mesmo RUN de apt-get update/install (--no-install-recommends) com limpeza
#     imediata de /var/lib/apt/lists/*.
#   - Sem instalacao de sudo e sem NOPASSWD:ALL.
#   - Criacao do usuario nao-root (dev) tratando colisao de UID/GID 1000 (que
#     ja pertence ao usuario 'ubuntu' na imagem oficial ubuntu:24.04), sem
#     senha (conta bloqueada para login por senha) e com shell /usr/bin/zsh.
#   - Troca para USER dev ANTES de executar install-terminal.sh.
#   - Nenhuma identidade Git pessoal ou credencial gravada na imagem.
# ==============================================================================

FROM ubuntu:24.04

ARG PROFILE=developer
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY . /opt/terminal-setup

RUN set -eux; \
    bash /opt/terminal-setup/scripts/install-system-packages.sh --profile "${PROFILE}"; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb; \
    if ! getent group "${USERNAME}" >/dev/null 2>&1; then \
      if getent group "${USER_GID}" >/dev/null 2>&1; then \
        groupadd "${USERNAME}"; \
      else \
        groupadd -g "${USER_GID}" "${USERNAME}"; \
      fi; \
    fi; \
    if ! id -u "${USERNAME}" >/dev/null 2>&1; then \
      if getent passwd "${USER_UID}" >/dev/null 2>&1; then \
        useradd -m -d "/home/${USERNAME}" -g "${USERNAME}" -s /usr/bin/zsh "${USERNAME}"; \
      else \
        useradd -m -d "/home/${USERNAME}" -u "${USER_UID}" -g "${USERNAME}" -s /usr/bin/zsh "${USERNAME}"; \
      fi; \
    fi; \
    passwd -l "${USERNAME}" >/dev/null 2>&1 || usermod -L "${USERNAME}"; \
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}" /opt/terminal-setup

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV HOME=/home/${USERNAME} \
    USER=${USERNAME} \
    SHELL=/usr/bin/zsh \
    PATH="/home/${USERNAME}/.local/bin:${PATH}"

RUN bash /opt/terminal-setup/install-terminal.sh \
      --profile "${PROFILE}" \
      --non-interactive \
      --skip-system-packages \
      --git-identity skip \
      --change-shell no

CMD ["/usr/bin/zsh", "-l"]

