#!/usr/bin/env bash
# Central SSH: instaladores externos executados somente apos confirmacao.
DTPROTO_INSTALL_URL='https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/install-server.sh'
SSHORIZON_INSTALL_URL='https://install.sshorizon.org/scripts/sshorizon.sh'

render_central_ssh_menu() {
  local selected="$1"
  clear_screen
  print_top
  center_title 'CENTRAL SSH'
  print_sep
  render_option "$selected" 0 '[1] Em breve (reservado)'
  render_option "$selected" 1 '[2] DTProto'
  render_option "$selected" 2 '[3] SSHorizon ( TG: @sshorizon_bot )'
  render_option "$selected" 3 '[4] BadVPN'
  print_sep
  render_option "$selected" 4 '[0] Voltar'
  print_bottom
  print_footer
}

# Usa arquivo temporario para checar integridade basica e evitar pipe remoto direto para bash.
executar_instalador_ssh() {
  local nome="$1" url="$2" temp_script status=0
  local dep
  for dep in curl bash mktemp rm; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      wait_enter_box 'DEPENDENCIA AUSENTE' "Instalador $nome nao iniciado." "Comando necessario: $dep"
      return 0
    fi
  done
  temp_script="$(mktemp /tmp/titanvps-ssh.XXXXXXXX.sh)" || {
    wait_enter_box "$nome" 'Falha ao criar arquivo temporario.'
    return 0
  }
  # EXIT/INT/TERM não deixam scripts temporários residuais após interrupção.
  # Subshell isola os traps do menu principal.
  _executar_instalador_ssh_temp "$nome" "$url" "$temp_script"
}
_executar_instalador_ssh_temp() (
  local nome="$1" url="$2" temp_script="$3" status=0
  trap 'rm -f -- "$temp_script"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf '\n  Baixando instalador %s...\n' "$nome"
  if curl -fsSL --connect-timeout 10 --max-time 90 --retry 2 --output "$temp_script" "$url" && [[ -s "$temp_script" ]] && bash -n "$temp_script"; then
    printf '\n  Iniciando instalador %s...\n\n' "$nome"
    bash "$temp_script" || status=$?
  else
    status=1
    printf '\n  Falha ao baixar ou validar o script %s.\n' "$nome"
  fi
  rm -f -- "$temp_script"
  if (( status == 0 )); then
    wait_enter_box "$nome" 'Instalador finalizado sem erros reportados.'
  else
    wait_enter_box "$nome" "Instalador encerrado com erro (codigo: $status)." 'Confira as mensagens acima.'
  fi
)

instalar_dtproto() {
  if confirm_with_menu 'INSTALAR DTPROTO' 'Baixar e executar o instalador do DTProto?' 'Origem: DTunnel0/DTProto-Server-Releases' 'Pode instalar servicos e alterar configuracoes de rede.'; then
    executar_instalador_ssh 'DTPROTO' "$DTPROTO_INSTALL_URL"
  fi
}

instalar_sshorizon() {
  if confirm_with_menu 'INSTALAR SSHORIZON' 'Baixar e executar o instalador do SSHorizon?' 'Origem: install.sshorizon.org' 'O instalador externo pode alterar servicos e configuracoes da VPS.'; then
    executar_instalador_ssh 'SSHORIZON' "$SSHORIZON_INSTALL_URL"
  fi
}

central_ssh_menu() {
  while true; do
    menu_select render_central_ssh_menu 5 0
    case "$MENU_SELECTED" in
      0) wait_enter_box 'CENTRAL SSH' 'A opcao 1 esta reservada para o proximo script.' ;;
      1) instalar_dtproto ;;
      2) instalar_sshorizon ;;
      3) badvpn_menu ;;
      4) return 0 ;;
    esac
  done
}
