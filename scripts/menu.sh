#!/usr/bin/env bash
set -Eeuo pipefail
# TITAN VPS: menu e navegacao. Operacoes executadas somente por selecao.
CYAN='\033[1;96m'
BLUE='\033[1;94m'
WHITE='\033[1;97m'
DIM='\033[0;37m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

BOX_TOP='┌────────────────────────────────────────┐'
BOX_SEP='├────────────────────────────────────────┤'
BOX_BOTTOM='└────────────────────────────────────────┘'
MENU_FOOTER='  ↑ ↓ Navegar     [Enter] Selecionar'
MENU_SELECTED=0
NAV_KEY=''
NAV_DIGIT=''

[[ ${EUID} -eq 0 ]] || {
  echo "Execute com sudo: sudo bash titanvps.sh" >&2
  exit 1
}

clear_screen() {
  # Quando a tela esta sendo preparada para renderizacao diferencial,
  # nao limpar o terminal dentro do renderer.
  [[ "${MENU_RENDER_BUFFERED:-0}" == 1 ]] && return 0
  [[ -t 1 ]] && clear 2>/dev/null || true
}

center_title() {
  local title="$1"
  local width=42
  local len=${#title}
  local left=$(( (width - len) / 2 ))
  (( left < 0 )) && left=0
  printf '%b%*s%s%b\n' "$WHITE" "$left" '' "$title" "$NC"
}

print_top() { printf '%b%s%b\n' "$BLUE" "$BOX_TOP" "$NC"; }
print_sep() { printf '%b%s%b\n' "$BLUE" "$BOX_SEP" "$NC"; }
print_bottom() { printf '%b%s%b\n' "$BLUE" "$BOX_BOTTOM" "$NC"; }
print_footer() { printf '%b%s%b\n' "$DIM" "$MENU_FOOTER" "$NC"; }

render_option() {
  local selected="$1" index="$2" label="$3"
  if (( selected == index )); then
    printf '%b> %s%b\n' "$CYAN" "$label" "$NC"
  else
    printf '%b  %s%b\n' "$WHITE" "$label" "$NC"
  fi
}

read_navigation() {
  local first='' rest=''
  NAV_KEY='other'
  NAV_DIGIT=''
  local read_status=0
  if [[ -n "${1:-}" ]]; then
    IFS= read -rsn1 -t "$1" first || read_status=$?
  else
    IFS= read -rsn1 first || read_status=$?
  fi
  if (( read_status != 0 )); then
    if (( read_status > 128 )); then NAV_KEY='timeout'; else NAV_KEY='eof'; fi
    return 0
  fi
  if [[ -z "$first" ]]; then
    NAV_KEY='enter'
    return 0
  fi
  if [[ "$first" == $'\e' ]]; then
    IFS= read -rsn2 -t 0.12 rest || true
    first+="$rest"
  fi
  case "$first" in
    $'\e[A') NAV_KEY='up' ;;
    $'\e[B') NAV_KEY='down' ;;
    [0-9]) NAV_KEY='digit'; NAV_DIGIT="$first" ;;
    [aA]) NAV_KEY='letter_a' ;;
    *) NAV_KEY='other' ;;
  esac
}

# Consulta periodica em segundo plano para nao travar setas/Enter nem piscar.
# Somente o processo do menu altera o estado das versoes e desenha no terminal.
GITHUB_POLL_SECONDS=60
VERSION_WATCH_PID=''
version_watch_start() {
  local result_dir="$1"
  # No máximo uma consulta por vez. Evita processos e downloads sobrepostos.
  if [[ -n "${VERSION_WATCH_PID:-}" ]] && kill -0 "$VERSION_WATCH_PID" 2>/dev/null; then
    return 0
  fi
  VERSION_WATCH_PID=''
  [[ -n "${result_dir:-}" ]] || return 0
  rm -f -- "$result_dir/result" "$result_dir/result.tmp"
  if ! github_is_configured || ! command -v curl >/dev/null 2>&1; then
    printf 'erro\n' > "$result_dir/result"
    return 0
  fi
  (
    if curl --fail --silent --location --connect-timeout 3 --max-time 7 --retry 0 \
      "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/version" \
      > "$result_dir/result.tmp" 2>/dev/null; then
      mv -f -- "$result_dir/result.tmp" "$result_dir/result"
    else
      printf 'erro\n' > "$result_dir/result"
      rm -f -- "$result_dir/result.tmp"
    fi
  ) </dev/null >/dev/null 2>&1 &
  VERSION_WATCH_PID=$!
}
version_watch_collect() {
  local result_dir="$1" latest
  [[ -f "$result_dir/result" ]] || return 0
  latest="$(tr -d '\r\n' < "$result_dir/result" 2>/dev/null || true)"
  rm -f -- "$result_dir/result"
  if valid_version "$latest"; then
    get_local_version
    REMOTE_VERSION="$latest"
    UPDATE_AVAILABLE=0
    version_greater "$REMOTE_VERSION" "$CURRENT_VERSION" && UPDATE_AVAILABLE=1
    UPDATE_CHECK_ERROR=''
  else
    UPDATE_CHECK_ERROR='Nao foi possivel consultar o GitHub.'
    # Nao declarar a versao atual como remota se a consulta falhar.
  fi
}

# Redesenha apenas linhas alteradas, sem limpar a tela a cada tecla.
# Terminal sem cursor ANSI continua usando a renderizacao tradicional.
menu_select() {
  local renderer="$1" count="$2" selected="${3:-0}"
  local -a previous=() current=()
  local i limit
  local differential=0
  local watch_dir='' watch_next=0 watch_enabled=0
  if [[ "$renderer" == 'render_main_menu' ]]; then
    watch_enabled=1
    watch_dir="$(mktemp -d)"
    version_watch_start "$watch_dir"
    watch_next=$(( SECONDS + GITHUB_POLL_SECONDS ))
  fi
  [[ -t 1 && -t 0 && "${TERM:-dumb}" != dumb ]] && differential=1
  if (( differential )); then
    clear_screen
    printf '\033[?25l'
  fi
  while true; do
    if (( watch_enabled )); then
      version_watch_collect "$watch_dir"
      if (( SECONDS >= watch_next )); then
        version_watch_start "$watch_dir"
        watch_next=$(( SECONDS + GITHUB_POLL_SECONDS ))
      fi
    fi
    if (( differential )); then
      # Captura a composicao completa em memoria antes de emitir bytes no terminal.
      # Evita apagar/desenhar a moldura inteira ao navegar no Termius.
      mapfile -t current < <(MENU_RENDER_BUFFERED=1 "$renderer" "$selected")
      limit=${#current[@]}
      (( ${#previous[@]} > limit )) && limit=${#previous[@]}
      for ((i=0; i<limit; i++)); do
        if [[ "${previous[i]-}" != "${current[i]-}" ]]; then
          printf '\033[%d;1H\033[2K%s' "$((i+1))" "${current[i]-}"
        fi
      done
      printf '\033[%d;1H' "$((limit+1))"
      previous=("${current[@]}")
    else
      "$renderer" "$selected"
    fi
    if (( watch_enabled )); then read_navigation 0.5; else read_navigation; fi
    case "$NAV_KEY" in
      up) selected=$(( (selected - 1 + count) % count )) ;;
      down) selected=$(( (selected + 1) % count )) ;;
      letter_a)
        if [[ "$renderer" == 'render_main_menu' ]]; then
          # Atalho A executa a opcao mesmo quando ela ja esta destacada.
          selected=0
          MENU_SELECTED=0
          break
        fi
        ;;
      digit)
        if [[ "$NAV_DIGIT" == "0" ]]; then
          selected=$((count - 1))
        else
          # O menu principal tem A antes de [1]; submenus comecam em [1].
          local offset=0 numeric_index
          [[ "$renderer" == 'render_main_menu' ]] && offset=1
          numeric_index=$((10#$NAV_DIGIT - 1 + offset))
          if (( numeric_index >= 0 && numeric_index < count - 1 )); then
            selected=$numeric_index
          fi
        fi
        ;;
      enter)
        MENU_SELECTED="$selected"
        break
        ;;
      eof)
        MENU_SELECTED=$((count - 1))
        break
        ;;
      *) ;;
    esac
  done
  if (( watch_enabled )); then
    if [[ -n "${VERSION_WATCH_PID:-}" ]]; then
      kill "$VERSION_WATCH_PID" 2>/dev/null || true
      wait "$VERSION_WATCH_PID" 2>/dev/null || true
      VERSION_WATCH_PID=''
    fi
    rm -rf -- "$watch_dir"
  fi
  if (( differential )); then
    printf '\033[?25h\033[%d;1H\033[J' "$((limit+1))"
  fi
  return 0
}

wait_enter_box() {
  local title="$1"
  shift || true
  clear_screen
  print_top
  center_title "$title"
  print_sep
  local line
  for line in "$@"; do
    printf '  %s\n' "$line"
  done
  print_sep
  printf '  Pressione [Enter] para continuar.\n'
  print_bottom
  IFS= read -r _ || true
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/operacoes.sh"
source "$SCRIPT_DIR/badvpn.sh"
source "$SCRIPT_DIR/formatar.sh"
source "$SCRIPT_DIR/atualizador.sh"
check_github_version
source "$SCRIPT_DIR/central_ssh.sh"
source "$SCRIPT_DIR/status.sh"

render_main_menu() {
  local selected="$1"
  clear_screen
  print_top
  center_title "TITAN VPS"
  print_sep
  titanvps_render_active_services
  # Os prefixos '> ' e '  ' usam exatamente duas colunas em todos os itens.
  # Não imprimir espaços extras na opção A, que é a mais longa do menu.
  if (( selected == 0 )); then
    printf '%b> [A] Atualizar Script%b (' "$CYAN" "$WHITE"
  else
    printf '%b  [A] Atualizar Script (' "$WHITE"
  fi
  if [[ -n "$UPDATE_CHECK_ERROR" ]]; then
    printf '%ba%s / n?%b' "$DIM" "$CURRENT_VERSION" "$WHITE"
  elif [[ "$CURRENT_VERSION" == "$REMOTE_VERSION" ]] || (( ! UPDATE_AVAILABLE )); then
    printf '%ba%s / n%s%b' "$DIM" "$CURRENT_VERSION" "$REMOTE_VERSION" "$WHITE"
  else
    printf '%ba%s%b / %bn%s%b' "$RED" "$CURRENT_VERSION" "$WHITE" "$GREEN" "$REMOTE_VERSION" "$WHITE"
  fi
  printf ')%b\n' "$NC"
  print_sep
  render_option "$selected" 1 "[1] Atualizar Servidor"
  render_option "$selected" 2 "[2] Alterar Senha Root"
  render_option "$selected" 3 "[3] Formatar Servidor"
  print_sep
  render_option "$selected" 4 "[4] Central SSH"
  print_sep
  render_option "$selected" 5 "[0] Sair"
  print_bottom
  print_footer
}

main_menu() {
  while true; do
    titanvps_refresh_active_labels
    menu_select render_main_menu 6 0
    case "$MENU_SELECTED" in
      0) atualizar_script; check_github_version ;;
      1) atualizar_servidor ;;
      2) alterar_senha_root ;;
      3) formatar_servidor ;;
      4) central_ssh_menu ;;
      5) clear_screen; return 0 ;;
    esac
  done
}

main_menu
