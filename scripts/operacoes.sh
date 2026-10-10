#!/usr/bin/env bash
# Operações locais do servidor. Não altera configurações do SSH.

atualizar_servidor() {
  clear_screen
  print_top
  center_title 'ATUALIZAR SERVIDOR'
  print_sep
  printf '  Atualizando índices e pacotes do sistema.\n'
  printf '  A operação pode exigir tempo e conexão.\n'
  print_bottom
  if ! command -v apt-get >/dev/null 2>&1 || ! command -v apt >/dev/null 2>&1; then
    wait_enter_box 'ERRO' 'APT não encontrado neste servidor.'
    return 0
  fi
  clear_screen
  printf '%bAtualizando servidor...%b\n\n' "$CYAN" "$NC"
  # Preserva a ordem e o comportamento de && da sequência solicitada.
  local result=0
  ( apt-get update -y && apt-get upgrade -y && apt update && apt upgrade -y ) || result=$?
  if (( result == 0 )); then
    return 0
  else
    wait_enter_box 'ATUALIZAÇÃO INTERROMPIDA' "Falha na execução (código: $result)." 'Confira as mensagens acima.'
  fi
}

# Instalador SSHPlus obtido em tempo de execucao, com validacao de sintaxe.
SENHAROOT_URL='https://sshplus.xyz/utilitarios/senharoot.sh'
alterar_senha_root() {
  local dep tmp='' status=0 senha_antes='' senha_depois=''
  for dep in curl bash mktemp awk systemctl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      wait_enter_box 'ERRO' "Dependencia ausente: $dep"
      return 0
    fi
  done
  if [[ ! -r /etc/shadow ]]; then
    wait_enter_box 'ERRO' 'Nao foi possivel verificar a senha root.'
    return 0
  fi
  senha_antes="$(awk -F: '$1=="root" {print $2}' /etc/shadow)"
  tmp="$(mktemp /tmp/titanvps-senharoot.XXXXXXXX.sh)" || { wait_enter_box 'ERRO' 'Falha ao criar temporario.'; return 0; }
  if ! curl -fsSL --connect-timeout 10 --max-time 90 --retry 2 --output "$tmp" "$SENHAROOT_URL" || [[ ! -s "$tmp" ]] || ! bash -n "$tmp"; then
    rm -f -- "$tmp"
    wait_enter_box 'ERRO' 'Falha no download ou sintaxe do instalador de senha.'
    return 0
  fi
  clear_screen
  printf '%bALTERAR SENHA ROOT%b\n\n' "$CYAN" "$NC"
  bash "$tmp" || status=$?
  rm -f -- "$tmp"
  if (( status != 0 )); then
    wait_enter_box 'ERRO' "Alteracao nao concluida (codigo $status)."
    return 0
  fi
  senha_depois="$(awk -F: '$1=="root" {print $2}' /etc/shadow)"
  if [[ -z "$senha_depois" || "$senha_antes" == "$senha_depois" ]]; then
    printf '\n  Senha root nao alterada; reinicio cancelado.\n'
    sleep 2
    return 0
  fi
  printf '\n%bREINICIANDO SERVIDOR...%b\n' "$CYAN" "$NC"
  if ! systemctl reboot; then
    wait_enter_box 'ERRO' 'Falha ao reiniciar o servidor.'
  fi
}
