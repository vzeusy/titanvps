#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$root/titanvps.sh" "$root/scripts/"*.sh; do bash -n "$f"; done
[[ -f "$root/.titanvps/github.conf" && -f "$root/version" && -f "$root/scripts/status.sh" ]]
grep -q titanvps_render_active_services "$root/scripts/menu.sh"
grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$root/version"
! grep -R -n -E 'gerenciador\.sh|gerenciador-backup|gerenciador-badvpn|gerenciador-ssh|Não será realizada remoção do painel' "$root/scripts" "$root/README.md"
echo 'OK: sintaxe, arquivos e referencias.'

# A opção A deve usar a mesma coluna das demais e caber em 42 colunas.
! grep -Fq "printf '%b  > [A]" "$root/scripts/menu.sh"
grep -Fq "printf '%b> [A] Atualizar Script ('" "$root/scripts/menu.sh"

# Instalacao e atualizacao devem registrar o comando global.
grep -Fq "/usr/local/bin/titanvps" "$root/titanvps.sh"
grep -Fq "/usr/local/bin/titanvps" "$root/scripts/atualizador.sh"

# Atualizacao nao deve sair do menu nem solicitar Enter ao concluir.
! grep -Fq 'ATUALIZACAO CONCLUIDA' "$root/scripts/atualizador.sh"
grep -Fq 'exec /bin/bash "$TITANVPS_ROOT/scripts/menu.sh"' "$root/scripts/atualizador.sh"
! grep -Fq 'return 2' "$root/scripts/atualizador.sh"

# Atalhos do menu principal: A = indice 0; 1 = indice 1.
grep -Fq 'MENU_SELECTED=0' "$root/scripts/menu.sh"
grep -Fq "[[ \"\$renderer\" == 'render_main_menu' ]] && offset=1" "$root/scripts/menu.sh"
! grep -Fq 'MENU_HAS_UPDATE' "$root/scripts/menu.sh"
