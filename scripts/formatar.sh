#!/usr/bin/env bash
# Interface para o VPS Reinstaller utilizado no script de referencia.
# Nenhuma formatacao e iniciada automaticamente por este modulo.
REINSTALLER_INSTALL_URL='https://raw.githubusercontent.com/nandoslayer/vps-reinstaller/main/install.sh'
REINSTALLER_BIN='/usr/local/bin/vps-reinstaller'

formatar_servidor() {
  clear_screen
  print_top
  center_title 'FORMATAR SERVIDOR'
  print_sep
  printf '  ATENCAO: Operacao destrutiva.\n'
  printf '  Pode apagar TODOS os dados da VPS.\n'
  printf '  O acesso SSH pode ser interrompido.\n'
  printf '  Mantenha backup externo e console VPS.\n'
  print_bottom
  if [[ ! -x "$REINSTALLER_BIN" ]]; then
    local dep
    for dep in curl bash mktemp rm; do
      if ! command -v "$dep" >/dev/null 2>&1; then
        wait_enter_box 'DEPENDENCIA AUSENTE' "Comando necessario: $dep" 'Instalacao nao iniciada.'
        return 0
      fi
    done
    local tempdir installer
    tempdir="$(mktemp -d)" || { wait_enter_box 'ERRO' 'Falha ao criar diretorio temporario.'; return 1; }
    installer="$tempdir/install.sh"
    if ! command -v curl >/dev/null 2>&1; then
      rm -rf -- "$tempdir"
      wait_enter_box 'ERRO' 'curl nao instalado; instale curl primeiro.'
      return 0
    fi
    if ! curl --fail --location --silent --show-error --connect-timeout 15 --max-time 90 "$REINSTALLER_INSTALL_URL" -o "$installer" || [[ ! -s "$installer" ]]; then
      rm -rf -- "$tempdir"
      wait_enter_box 'ERRO' 'Falha ao baixar instalador.'
      return 0
    fi
    if ! bash -n "$installer"; then
      rm -rf -- "$tempdir"
      wait_enter_box 'ERRO' 'Script externo com sintaxe invalida.'
      return 0
    fi
    printf '\n  Executando instalacao da ferramenta...\n'
    if ! (cd /root && bash "$installer"); then
      rm -rf -- "$tempdir"
      wait_enter_box 'ERRO' 'Instalacao do VPS Reinstaller falhou.'
      return 0
    fi
    rm -rf -- "$tempdir"
    if [[ -x /root/vps-reinstaller && ! -x "$REINSTALLER_BIN" ]]; then
      install -m 0755 /root/vps-reinstaller "$REINSTALLER_BIN" || true
    fi
  fi

  if [[ ! -x "$REINSTALLER_BIN" ]]; then
    wait_enter_box 'ERRO' 'VPS Reinstaller nao foi encontrado.'
    return 0
  fi
  clear_screen
  # A ferramenta externa nao fornece um sinal documentado de confirmacao
  # da reinstalacao. Retorno zero dispara reboot sem confirmacao adicional.
  local reinstaller_exit=0
  "$REINSTALLER_BIN" || reinstaller_exit=$?
  if (( reinstaller_exit != 0 )); then
    wait_enter_box 'FORMATAR SERVIDOR' \
      "O reinstalador encerrou com erro (codigo $reinstaller_exit)." \
      'Nenhum reboot automatico foi iniciado.'
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    wait_enter_box 'ERRO' 'systemctl ausente; reinicio nao executado.'
    return 0
  fi
  printf '\n  REINICIANDO SERVIDOR...\n'
  if ! systemctl reboot; then
    wait_enter_box 'ERRO' 'Nao foi possivel reiniciar o servidor.'
  fi
}
