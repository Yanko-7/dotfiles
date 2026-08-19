#!/usr/bin/env bash
set -Eeuo pipefail

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || die "This script currently targets Linux."

LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"
PLUGIN_DIR="$HOME/.local/share/zsh/plugins"
mkdir -p "$LOCAL_BIN" "$LOCAL_OPT" "$PLUGIN_DIR" "$HOME/.local/state/zsh" "$HOME/.cache/zsh"
export PATH="$LOCAL_BIN:$PATH"

if [[ $EUID -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  die "sudo is required for installing system packages."
fi

log "Installing base packages"
if command -v apt-get >/dev/null 2>&1; then
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    zsh git curl ca-certificates tar gzip unzip ripgrep bat fd-find
elif command -v dnf >/dev/null 2>&1; then
  "${SUDO[@]}" dnf install -y \
    zsh git curl ca-certificates tar gzip unzip ripgrep bat fd-find
elif command -v pacman >/dev/null 2>&1; then
  "${SUDO[@]}" pacman -Syu --needed --noconfirm \
    zsh git curl ca-certificates tar gzip unzip ripgrep bat fd
else
  die "Supported package managers: apt, dnf, pacman."
fi

# Debian/Ubuntu package names differ from the executable names.
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  ln -sfn "$(command -v batcat)" "$LOCAL_BIN/bat"
fi
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"
fi

case "$(uname -m)" in
  x86_64|amd64)
    EZA_ARCH="x86_64"
    NVIM_ARCH="x86_64"
    ;;
  aarch64|arm64)
    EZA_ARCH="aarch64"
    NVIM_ARCH="arm64"
    ;;
  *)
    die "Unsupported CPU architecture: $(uname -m)"
    ;;
esac

log "Installing latest eza"
curl -fsSL \
  "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" \
  | tar xz -C "$LOCAL_BIN"
chmod +x "$LOCAL_BIN/eza"

log "Installing latest stable Neovim"
NVIM_NAME="nvim-linux-${NVIM_ARCH}"
TMP_NVIM="$(mktemp -d)"
trap 'rm -rf "${TMP_NVIM:-}"' EXIT
curl -fL \
  "https://github.com/neovim/neovim/releases/latest/download/${NVIM_NAME}.tar.gz" \
  -o "$TMP_NVIM/nvim.tar.gz"
rm -rf "$LOCAL_OPT/$NVIM_NAME"
tar -xzf "$TMP_NVIM/nvim.tar.gz" -C "$LOCAL_OPT"
ln -sfn "$LOCAL_OPT/$NVIM_NAME/bin/nvim" "$LOCAL_BIN/nvim"

log "Installing latest fzf"
if [[ -d "$HOME/.fzf/.git" ]]; then
  git -C "$HOME/.fzf" pull --ff-only
else
  rm -rf "$HOME/.fzf"
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
fi
"$HOME/.fzf/install" --bin
ln -sfn "$HOME/.fzf/bin/fzf" "$LOCAL_BIN/fzf"

log "Installing latest zoxide"
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

log "Installing latest Starship"
TMP_STARSHIP="$(mktemp)"
curl -fsSL https://starship.rs/install.sh -o "$TMP_STARSHIP"
sh "$TMP_STARSHIP" -y -b "$LOCAL_BIN"
rm -f "$TMP_STARSHIP"

clone_or_update() {
  local repo="$1"
  local name="$2"
  local dir="$PLUGIN_DIR/$name"

  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only
  else
    rm -rf "$dir"
    git clone --depth 1 "https://github.com/$repo.git" "$dir"
  fi
}

log "Installing Zsh plugins"
clone_or_update zdharma-continuum/fast-syntax-highlighting fast-syntax-highlighting
clone_or_update zsh-users/zsh-autosuggestions zsh-autosuggestions
clone_or_update zsh-users/zsh-history-substring-search zsh-history-substring-search
clone_or_update jeffreytse/zsh-vi-mode zsh-vi-mode

log "Configuring ~/.zshrc"
ZSHRC="$HOME/.zshrc"
BEGIN_MARKER="# >>> modern-zsh-bootstrap >>>"
END_MARKER="# <<< modern-zsh-bootstrap <<<"

if [[ -f "$ZSHRC" && ! -f "$HOME/.zshrc.before-modern-zsh" ]]; then
  cp "$ZSHRC" "$HOME/.zshrc.before-modern-zsh"
fi

TMP_ZSHRC="$(mktemp)"
if [[ -f "$ZSHRC" ]]; then
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip       { print }
  ' "$ZSHRC" > "$TMP_ZSHRC"
fi
cat "$TMP_ZSHRC" > "$ZSHRC"
rm -f "$TMP_ZSHRC"

cat >> "$ZSHRC" <<'ZSHRC'

# >>> modern-zsh-bootstrap >>>
export PATH="$HOME/.local/bin:$PATH"
export EDITOR="nvim"
export VISUAL="nvim"

# History
HISTFILE="$HOME/.local/state/zsh/history"
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS

# Completion
autoload -Uz compinit
mkdir -p "$HOME/.cache/zsh"
compinit -d "$HOME/.cache/zsh/zcompdump-$ZSH_VERSION"

# Modern CLI defaults
alias ls='eza --icons=auto --group-directories-first'
alias ll='eza -lah --icons=auto --git --group-directories-first'
alias la='eza -a --icons=auto --group-directories-first'
alias tree='eza --tree --icons=auto'
alias cat='bat'
alias vim='nvim'

# fzf + fd + bat
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"

# Plugins: syntax highlighting must come before history-substring-search.
source "$HOME/.local/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
source "$HOME/.local/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$HOME/.local/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh"

# Start zsh-vi-mode in insert mode.
function zvm_config() {
  ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
}

# zsh-vi-mode may overwrite existing keybindings, so install fzf/history
# bindings after zsh-vi-mode initializes.
function zvm_after_init() {
  source <(fzf --zsh)

  if [[ -n "${terminfo[kcuu1]:-}" ]]; then
    bindkey -M viins "$terminfo[kcuu1]" history-substring-search-up
  fi
  if [[ -n "${terminfo[kcud1]:-}" ]]; then
    bindkey -M viins "$terminfo[kcud1]" history-substring-search-down
  fi

  bindkey -M viins '^[[A' history-substring-search-up
  bindkey -M viins '^[[B' history-substring-search-down
}
source "$HOME/.local/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh"

# Smarter cd and prompt
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
# <<< modern-zsh-bootstrap <<<
ZSHRC

log "Verifying installation"
printf '%-12s %s\n' zsh      "$(zsh --version | head -n1)"
printf '%-12s %s\n' nvim     "$(nvim --version | head -n1)"
printf '%-12s %s\n' eza      "$(eza --version | head -n1)"
printf '%-12s %s\n' bat      "$(bat --version | head -n1)"
printf '%-12s %s\n' fd       "$(fd --version | head -n1)"
printf '%-12s %s\n' fzf      "$(fzf --version | head -n1)"
printf '%-12s %s\n' zoxide   "$(zoxide --version | head -n1)"
printf '%-12s %s\n' starship "$(starship --version | head -n1)"
printf '%-12s %s\n' rg       "$(rg --version | head -n1)"

ZSH_PATH="$(command -v zsh)"
if command -v chsh >/dev/null 2>&1 && [[ "${SHELL:-}" != "$ZSH_PATH" ]]; then
  log "Setting Zsh as the default shell"
  chsh -s "$ZSH_PATH" || warn "chsh failed; run manually: chsh -s $ZSH_PATH"
fi

cat <<EOF

Done.

Start it now with:
  exec zsh

Config:
  $HOME/.zshrc

Plugins:
  $PLUGIN_DIR

If an old ~/.zshrc existed, the first-run backup is:
  $HOME/.zshrc.before-modern-zsh
EOF
