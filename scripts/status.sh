#!/usr/bin/env bash
# Somente serviços efetivamente ativos; sem exibir serviços ausentes/parados.
# Atualiza a cada desenho do menu.
titanvps_service_active() {
  local unit
  command -v systemctl >/dev/null 2>&1 || return 1
  for unit in "$@"; do
    systemctl is-active --quiet "$unit" 2>/dev/null && return 0
  done
  return 1
}
titanvps_active_labels() {
  local -n result="$1"
  result=()
  if declare -F badvpn_status >/dev/null && [[ "$(badvpn_status)" == 'ATIVO' ]]; then
    result+=(BadVPN)
  fi
  # Detecta apenas unidades efetivamente ativas. Não confunde instalação com ativação.
  if titanvps_service_active dtproto.service dtproto-server.service DTProto.service; then
    result+=(DTProto)
  fi
  if titanvps_service_active sshorizon.service sshorizon-server.service sshorizon-panel.service; then
    result+=(SSHorizon)
  fi
}
titanvps_render_active_services() {
  local labels=() i
  titanvps_active_labels labels
  ((${#labels[@]})) || return 0
  print_sep
  for ((i=0;i<${#labels[@]};i+=2)); do
    if (( i+1 < ${#labels[@]} )); then
      printf '  🟢 %-16s 🟢 %s\n' "${labels[i]}" "${labels[i+1]}"
    else
      printf '  🟢 %s\n' "${labels[i]}"
    fi
  done
}
