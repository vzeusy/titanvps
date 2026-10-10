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
