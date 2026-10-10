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
  if ! confirm_with_menu 'CONFIRMAR ATUALIZAÇÃO' 'Atualizar os pacotes do servidor?' 'Pacotes instalados podem ser atualizados.'; then
    return 0
  fi
  clear_screen
  printf '%bAtualizando servidor...%b\n\n' "$CYAN" "$NC"
  # Preserva a ordem e o comportamento de && da sequência solicitada.
  local result=0
  ( apt-get update -y && apt-get upgrade -y && apt update && apt upgrade -y ) || result=$?
  if (( result == 0 )); then
    wait_enter_box 'ATUALIZAÇÃO CONCLUÍDA' 'Todos os comandos terminaram com sucesso.'
  else
    wait_enter_box 'ATUALIZAÇÃO INTERROMPIDA' "Falha na execução (código: $result)." 'Confira as mensagens acima.'
  fi
}

alterar_senha_root() {
  clear_screen
  if ! command -v chpasswd >/dev/null 2>&1; then
    wait_enter_box 'ERRO' 'Comando chpasswd não disponível.'
    return 0
  fi
  print_top
  center_title 'ALTERAR SENHA ROOT'
  print_sep
  printf '  A senha digitada ficará visível.\n'
  printf '  Evite terminais compartilhados ou gravados.\n'
  print_sep
  local nova_senha=''
  printf '  DIGITE A SENHA ROOT: '
  if ! IFS= read -r nova_senha; then
    printf '\n'
    wait_enter_box 'CANCELADO' 'Nenhuma alteração realizada.'
    return 0
  fi
  if [[ -z "$nova_senha" || "$nova_senha" == *$'\r'* || "$nova_senha" == *:* || "$nova_senha" == *$'\n'* ]]; then
    nova_senha=''
    wait_enter_box 'SENHA INVÁLIDA' 'Digite uma senha não vazia, sem dois-pontos.'
    return 0
  fi
  local result=0
  # A senha é enviada via stdin; não aparece na linha de comando nem é salva em arquivo.
  printf 'root:%s\n' "$nova_senha" | chpasswd || result=$?
  nova_senha=''
  if (( result == 0 )); then
    wait_enter_box 'SENHA ALTERADA' 'Senha root atualizada com sucesso.' 'Configurações do SSH preservadas.'
  else
    wait_enter_box 'ERRO' 'Não foi possível alterar a senha root.' "Código de erro: $result"
  fi
}
