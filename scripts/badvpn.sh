#!/usr/bin/env bash
# BadVPN UDPGW independente, adaptado do fluxo vzeusx/vps/scripts/aws.sh.
BADVPN_SOURCE_DIR='/usr/local/src/badvpn'
BADVPN_BUILD_DIR="$BADVPN_SOURCE_DIR/build-udpgw"
BADVPN_SINGLE_PORT=7300
BADVPN_MULTI_PORTS=(7300 7400 3478)
BADVPN_UNIT='/etc/systemd/system/badvpn.service'
BADVPN_TEMPLATE='/etc/systemd/system/badvpn@.service'
BADVPN_TUNING='/etc/sysctl.d/99-titanvps-badvpn.conf'
BADVPN_BIN='/usr/local/bin/badvpn-udpgw'
BADVPN_LOG='/var/log/titanvps-badvpn.log'
BADVPN_LEGACY_TUNING='/etc/sysctl.d/99-gerenciador-badvpn.conf'

badvpn_installed() { [[ -x "$BADVPN_BIN" ]]; }
badvpn_multi() { [[ -f "$BADVPN_TEMPLATE" ]]; }
badvpn_optimized() { [[ -f "$BADVPN_TUNING" || -f "$BADVPN_LEGACY_TUNING" ]]; }
badvpn_status() {
  if ! badvpn_installed || [[ ! -f "$BADVPN_UNIT" ]]; then echo 'NÃO INSTALADO'; return; fi
  if badvpn_multi; then
    local port
    for port in "${BADVPN_MULTI_PORTS[@]}"; do
      if ! systemctl is-active --quiet "badvpn@${port}"; then
        echo 'PARCIAL / PARADO'; return
      fi
    done
    echo ATIVO
  elif systemctl is-active --quiet badvpn; then echo ATIVO
  else echo PARADO; fi
}
badvpn_profile() {
  local mem=0
  mem="$(awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo)"
  if (( mem <= 1024 )); then echo LOW
  elif (( mem <= 4096 )); then echo MEDIUM
  else echo HIGH; fi
}
badvpn_max_clients() {
  case "$(badvpn_profile)" in LOW) echo 512;; MEDIUM) echo 1000;; HIGH) echo 2000;; esac
}
badvpn_buffer() {
  badvpn_optimized || return 0
  case "$(badvpn_profile)" in
    LOW) echo ' --client-socket-sndbuf 1048576';;
    MEDIUM) echo ' --client-socket-sndbuf 2097152';;
    HIGH) echo ' --client-socket-sndbuf 4194304';;
  esac
}
badvpn_stop_units() {
  local port
  systemctl stop badvpn >/dev/null 2>&1 || true
  systemctl disable badvpn >/dev/null 2>&1 || true
  for port in "${BADVPN_MULTI_PORTS[@]}"; do
    systemctl stop "badvpn@${port}" >/dev/null 2>&1 || true
    systemctl disable "badvpn@${port}" >/dev/null 2>&1 || true
  done
}
badvpn_write_single() {
  cat > "$BADVPN_UNIT" <<EOFUNIT
[Unit]
Description=BadVPN UDPGW
After=network.target
[Service]
Type=simple
ExecStart=$BADVPN_BIN --listen-addr 0.0.0.0:$BADVPN_SINGLE_PORT --max-clients $(badvpn_max_clients)$(badvpn_buffer) --loglevel warning
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOFUNIT
}
badvpn_write_multi() {
  cat > "$BADVPN_TEMPLATE" <<EOFUNIT
[Unit]
Description=BadVPN UDPGW port %i
After=network.target
[Service]
Type=simple
ExecStart=$BADVPN_BIN --listen-addr 0.0.0.0:%i --max-clients $(badvpn_max_clients)$(badvpn_buffer) --loglevel warning
Restart=always
RestartSec=3
User=root
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOFUNIT
  cat > "$BADVPN_UNIT" <<EOFUNIT
[Unit]
Description=BadVPN UDPGW multiporta
After=network.target
Requires=badvpn@7300.service badvpn@7400.service badvpn@3478.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/bin/true
[Install]
WantedBy=multi-user.target
EOFUNIT
}
badvpn_apply_mode() (
  # Subshell mantem traps isolados e recupera a configuracao ao falhar/interromper.
  local mode="$1" port staged old_mode previous_running=0 committed=0
  for dep in systemctl mktemp cp rm; do
    command -v "$dep" >/dev/null 2>&1 || { echo "ERRO: dependencia ausente: $dep"; return 1; }
  done
  staged="$(mktemp -d /tmp/titanvps-badvpn.XXXXXXXX)" || return 1
  [[ -f "$BADVPN_UNIT" ]] && cp -a "$BADVPN_UNIT" "$staged/single.service" || true
  [[ -f "$BADVPN_TEMPLATE" ]] && cp -a "$BADVPN_TEMPLATE" "$staged/multi.service" || true
  old_mode=single
  [[ -f "$BADVPN_TEMPLATE" ]] && old_mode=multi
  if [[ "$old_mode" == multi ]]; then
    for port in "${BADVPN_MULTI_PORTS[@]}"; do
      systemctl is-active --quiet "badvpn@${port}" && previous_running=1 && break
    done
  elif systemctl is-active --quiet badvpn; then previous_running=1; fi
  _restore_badvpn() {
    local port
    badvpn_stop_units
    rm -f -- "$BADVPN_UNIT" "$BADVPN_TEMPLATE"
    [[ -f "$staged/single.service" ]] && cp -a "$staged/single.service" "$BADVPN_UNIT"
    [[ -f "$staged/multi.service" ]] && cp -a "$staged/multi.service" "$BADVPN_TEMPLATE"
    systemctl daemon-reload >/dev/null 2>&1 || true
    if (( previous_running )); then
      if [[ "$old_mode" == multi ]]; then
        for port in "${BADVPN_MULTI_PORTS[@]}"; do systemctl enable --now "badvpn@${port}" >/dev/null 2>&1 || true; done
      fi
      systemctl enable --now badvpn >/dev/null 2>&1 || true
    fi
  }
  _finish_badvpn() {
    if (( ! committed )); then
      echo 'Restaurando configuracao anterior do BadVPN...' >&2
      _restore_badvpn
    fi
    rm -rf -- "$staged"
  }
  trap _finish_badvpn EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  badvpn_stop_units
  if [[ "$mode" == multi ]]; then
    badvpn_write_multi
  else
    rm -f -- "$BADVPN_TEMPLATE"
    badvpn_write_single
  fi
  systemctl daemon-reload || return 1
  if [[ "$mode" == multi ]]; then
    for port in "${BADVPN_MULTI_PORTS[@]}"; do
      systemctl enable --now "badvpn@${port}" || return 1
      systemctl is-active --quiet "badvpn@${port}" || return 1
    done
  fi
  systemctl enable --now badvpn || return 1
  systemctl is-active --quiet badvpn || return 1
  committed=1
)
badvpn_run_action() {
  local label="$1"; shift
  if ! command -v flock >/dev/null 2>&1; then
    wait_enter_box 'DEPENDENCIA AUSENTE' 'flock e necessario para evitar alteracoes simultaneas de servicos.'
    return 0
  fi
  mkdir -p /run/lock
  local lock_fd
  exec {lock_fd}>/run/lock/titanvps-badvpn.lock
  if ! flock -n "$lock_fd"; then
    wait_enter_box 'BADVPN OCUPADO' 'Outra operacao do BadVPN esta em andamento.'
    exec {lock_fd}>&-
    return 0
  fi
  clear_screen
  printf '%b%s%b\n\n' "$CYAN" "$label" "$NC"
  local result=0
  "$@" >> "$BADVPN_LOG" 2>&1 || result=$?
  flock -u "$lock_fd"; exec {lock_fd}>&-
  if (( result == 0 )); then
    return 0
  else
    wait_enter_box 'ERRO BADVPN' "$label: falhou (código $result)." "Log: $BADVPN_LOG"
  fi
}
badvpn_install_impl() {
  local distro=''
  [[ -r /etc/os-release ]] && . /etc/os-release && distro="${ID:-}"
  case "$distro" in
    ubuntu|debian) apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y git cmake build-essential pkg-config ;;
    amzn|amazon) if command -v dnf >/dev/null; then dnf install -y git cmake make gcc gcc-c++ pkgconf-pkg-config; else yum install -y git cmake make gcc gcc-c++ pkgconfig; fi ;;
    *) printf 'Distribuição não suportada: %s\n' "$distro"; return 1 ;;
  esac
  mkdir -p /usr/local/src
  if [[ -d "$BADVPN_SOURCE_DIR/.git" ]]; then
    git -C "$BADVPN_SOURCE_DIR" fetch --depth 1 origin
    git -C "$BADVPN_SOURCE_DIR" reset --hard FETCH_HEAD
  elif [[ -e "$BADVPN_SOURCE_DIR" ]]; then
    echo 'Diretório de origem já existe e não é um repositório Git. Abortando para preservar os arquivos.'; return 1
  else
    git clone --depth 1 https://github.com/ambrop72/badvpn.git "$BADVPN_SOURCE_DIR"
  fi
  cmake -S "$BADVPN_SOURCE_DIR" -B "$BADVPN_BUILD_DIR" -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
  cmake --build "$BADVPN_BUILD_DIR" -j"$(nproc)"
  cmake --install "$BADVPN_BUILD_DIR"
  badvpn_installed || return 1
  if badvpn_multi; then badvpn_apply_mode multi; else badvpn_apply_mode single; fi
}
badvpn_restart_impl() {
  badvpn_installed || { echo 'BadVPN não instalado'; return 1; }
  if badvpn_multi; then badvpn_apply_mode multi; else systemctl restart badvpn && systemctl is-active --quiet badvpn; fi
}
badvpn_optimize_impl() {
  badvpn_installed || return 1
  if badvpn_optimized; then
    rm -f "$BADVPN_TUNING" "$BADVPN_LEGACY_TUNING"
  else
    local mem
    case "$(badvpn_profile)" in
      LOW) mem=4194304;; MEDIUM) mem=8388608;; HIGH) mem=16777216;;
    esac
    cat > "$BADVPN_TUNING" <<EOFOPT
# Ajuste dedicado para BadVPN; removível no menu.
net.core.rmem_max = $mem
net.core.wmem_max = $mem
EOFOPT
  fi
  if [[ -f "$BADVPN_TUNING" ]]; then rm -f "$BADVPN_LEGACY_TUNING"; fi
  sysctl --system
  if badvpn_multi; then badvpn_apply_mode multi; else badvpn_apply_mode single; fi
}
badvpn_remove_impl() {
  badvpn_stop_units
  rm -f "$BADVPN_UNIT" "$BADVPN_TEMPLATE" "$BADVPN_TUNING" "$BADVPN_LEGACY_TUNING"
  systemctl daemon-reload
  sysctl --system
  if [[ -x "$BADVPN_BIN" ]]; then rm -f "$BADVPN_BIN"; fi
  # Código-fonte só é removido se corresponder ao repositório esperado.
  if [[ -d "$BADVPN_SOURCE_DIR/.git" ]] && [[ "$(git -C "$BADVPN_SOURCE_DIR" remote get-url origin 2>/dev/null || true)" == 'https://github.com/ambrop72/badvpn.git' ]]; then
    rm -rf "$BADVPN_SOURCE_DIR"
  fi
}
render_badvpn_menu() {
  local selected="$1" mode='PORTA ÚNICA' ports="$BADVPN_SINGLE_PORT" opt='INATIVA'
  badvpn_multi && mode='MULTIPORTA' && ports='7300 7400 3478'
  badvpn_optimized && opt="ATIVA ($(badvpn_profile))"
  clear_screen
  print_top
  center_title 'GERENCIAR BADVPN'
  print_sep
  printf '  Status: %s\n  Modo: %s\n  Portas: %s\n  Otimização: %s\n' "$(badvpn_status)" "$mode" "$ports" "$opt"
  print_sep
  render_option "$selected" 0 '[1] Instalar / Atualizar BadVPN'
  render_option "$selected" 1 '[2] Reiniciar BadVPN'
  render_option "$selected" 2 '[3] Ativar Multiporta'
  render_option "$selected" 3 '[4] Reiniciar Multiporta'
  render_option "$selected" 4 '[5] Remover Multiporta'
  render_option "$selected" 5 '[6] Ativar / Desativar Otimização'
  render_option "$selected" 6 '[7] Remover BadVPN'
  print_sep
  render_option "$selected" 7 '[0] Voltar'
  print_bottom
  print_footer
}
badvpn_menu() {
  local mode
  while true; do
    menu_select render_badvpn_menu 8 0
    case "$MENU_SELECTED" in
      0) badvpn_run_action 'Instalar / Atualizar' badvpn_install_impl ;;
      1) badvpn_run_action 'Reiniciar BadVPN' badvpn_restart_impl ;;
      2) if badvpn_installed; then badvpn_run_action 'Ativar Multiporta' badvpn_apply_mode multi; else wait_enter_box 'BADVPN' 'Instale o BadVPN primeiro.'; fi ;;
      3) if badvpn_multi; then badvpn_run_action 'Reiniciar Multiporta' badvpn_apply_mode multi; else wait_enter_box 'BADVPN' 'O modo multiporta não está ativo.'; fi ;;
      4) if badvpn_multi; then badvpn_run_action 'Remover Multiporta' badvpn_apply_mode single; else wait_enter_box 'BADVPN' 'O modo multiporta não está ativo.'; fi ;;
      5) badvpn_run_action 'Alternar Otimização' badvpn_optimize_impl ;;
      6) badvpn_run_action 'Remover BadVPN' badvpn_remove_impl ;;
      7) return 0 ;;
    esac
  done
}
