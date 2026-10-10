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
  if ! IFS= read -rsn1 first; then
    NAV_KEY='eof'
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

# Redesenha apenas linhas alteradas, sem limpar a tela a cada tecla.
# Terminal sem cursor ANSI continua usando a renderizacao tradicional.
menu_select() {
  local renderer="$1" count="$2" selected="${3:-0}"
  local -a previous=() current=()
  local i limit
  local differential=0
  [[ -t 1 && -t 0 && "${TERM:-dumb}" != dumb ]] && differential=1
  if (( differential )); then
    clear_screen
    printf '\033[?25l'
  fi
  while true; do
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
    read_navigation
    case "$NAV_KEY" in
      up) selected=$(( (selected - 1 + count) % count )) ;;
      down) selected=$(( (selected + 1) % count )) ;;
      letter_a)
        if [[ "$renderer" == 'render_main_menu' ]]; then selected=0; fi
        ;;
      digit)
        if [[ "$NAV_DIGIT" == "0" ]]; then
          selected=$((count - 1))
        else
          local numeric_index=$((10#$NAV_DIGIT - 1 + ${MENU_HAS_UPDATE:-0}))
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

CONFIRM_TITLE='CONFIRMAR'
CONFIRM_CONTINUE_LABEL='[1] Continuar'
CONFIRM_LINES=()

render_confirmation_menu() {
  local selected="$1" line
  clear_screen
  print_top
  center_title "$CONFIRM_TITLE"
  print_sep
  for line in "${CONFIRM_LINES[@]}"; do
    printf '  %s\n' "$line"
  done
  print_sep
  render_option "$selected" 0 "$CONFIRM_CONTINUE_LABEL"
  print_sep
  render_option "$selected" 1 "[0] Voltar"
  print_bottom
  print_footer
}

confirm_with_menu() {
  local title="$1"
  shift || true
  CONFIRM_TITLE="$title"
  CONFIRM_CONTINUE_LABEL='[1] Continuar'
  CONFIRM_LINES=("$@")
  menu_select render_confirmation_menu 2 0
  (( MENU_SELECTED == 0 ))
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
    printf '%b> [A] Atualizar Script (' "$CYAN"
    printf 'v%s / v%s' "$CURRENT_VERSION" "$REMOTE_VERSION"
    printf ')%b\n' "$NC"
  else
    printf '%b  [A] Atualizar Script (%b' "$WHITE" "$NC"
    print_update_version_label
    printf '%b)%b\n' "$WHITE" "$NC"
  fi
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
    menu_select render_main_menu 6 0
    case "$MENU_SELECTED" in
      0) atualizar_script || { local code=$?; if (( code == 2 )); then return 0; fi; } ; check_github_version ;;
      1) atualizar_servidor ;;
      2) alterar_senha_root ;;
      3) formatar_servidor ;;
      4) central_ssh_menu ;;
      5) clear_screen; return 0 ;;
    esac
  done
}

main_menu
