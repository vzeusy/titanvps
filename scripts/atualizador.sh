#!/usr/bin/env bash
# Atualizacao de releases publicados pelo proprietario no GitHub.
TITANVPS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Configuracoes locais preservadas durante a atualizacao.
if [[ ! -f "$TITANVPS_ROOT/.titanvps/github.conf" && -f "$TITANVPS_ROOT/github.conf" ]]; then
  mkdir -p "$TITANVPS_ROOT/.titanvps"
  cp -p "$TITANVPS_ROOT/github.conf" "$TITANVPS_ROOT/.titanvps/github.conf"
fi
if [[ -f "$TITANVPS_ROOT/.titanvps/github.conf" ]]; then
  source "$TITANVPS_ROOT/.titanvps/github.conf"
else
  GITHUB_USER='vzeusy'
  GITHUB_REPO='titanvps'
  GITHUB_BRANCH='main'
fi
VERSION_FILE="$TITANVPS_ROOT/version"
CURRENT_VERSION='0.0.1'
REMOTE_VERSION=''
UPDATE_AVAILABLE=0
UPDATE_CHECK_ERROR=''

valid_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; }
version_greater() {
  local a b c x y z
  IFS=. read -r a b c <<< "$1"
  IFS=. read -r x y z <<< "$2"
  (( 10#$a > 10#$x || (10#$a == 10#$x && 10#$b > 10#$y) || (10#$a == 10#$x && 10#$b == 10#$y && 10#$c > 10#$z) ))
}
get_local_version() {
  local value
  value="$(tr -d '\r\n' < "$VERSION_FILE" 2>/dev/null || true)"
  if valid_version "$value"; then CURRENT_VERSION="$value"; else CURRENT_VERSION='0.0.1'; fi
}
github_is_configured() {
  [[ "$GITHUB_USER" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ && "$GITHUB_REPO" =~ ^[A-Za-z0-9._-]+$ && "$GITHUB_BRANCH" =~ ^[A-Za-z0-9._/-]+$ && "$GITHUB_BRANCH" != *'..'* && "$GITHUB_BRANCH" != /* && "$GITHUB_BRANCH" != */ ]] &&
  [[ "$GITHUB_USER" != 'SEU_USUARIO' && "$GITHUB_REPO" != 'SEU_REPOSITORIO' ]]
}
check_github_version() {
  get_local_version
  REMOTE_VERSION="$CURRENT_VERSION"
  UPDATE_AVAILABLE=0
  UPDATE_CHECK_ERROR=''
  if ! github_is_configured; then
    UPDATE_CHECK_ERROR='Configure .titanvps/github.conf para ativar as atualizacoes.'
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    UPDATE_CHECK_ERROR='curl nao instalado.'
    return 0
  fi
  local result
  result="$(curl --fail --silent --show-error --location --connect-timeout 3 --max-time 7 --retry 0 "https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/version" 2>/dev/null)" || {
    UPDATE_CHECK_ERROR='Nao foi possivel consultar o GitHub.'
    return 0
  }
  result="$(printf '%s' "$result" | tr -d '\r\n')"
  if ! valid_version "$result"; then
    UPDATE_CHECK_ERROR='Arquivo version remoto invalido.'
    return 0
  fi
  REMOTE_VERSION="$result"
  if version_greater "$REMOTE_VERSION" "$CURRENT_VERSION"; then UPDATE_AVAILABLE=1; fi
}
print_update_version_label() {
  if [[ "$CURRENT_VERSION" == "$REMOTE_VERSION" ]] || (( ! UPDATE_AVAILABLE )); then
    printf '%ba%s / n%s%b' '\033[0;37m' "$CURRENT_VERSION" "$REMOTE_VERSION" '\033[0m'
  else
    printf '%ba%s%b / %bn%s%b' '\033[1;31m' "$CURRENT_VERSION" '\033[0m' '\033[1;32m' "$REMOTE_VERSION" '\033[0m'
  fi
}

atualizar_script() {
  check_github_version
  if [[ -n "$UPDATE_CHECK_ERROR" ]]; then
    wait_enter_box 'ATUALIZACAO DO SCRIPT' "$UPDATE_CHECK_ERROR" 'Nenhuma alteracao realizada.'
    return 0
  fi
  if (( ! UPDATE_AVAILABLE )); then
    # Sem versao nova: manter o menu principal, sem aviso ou espera por Enter.
    return 0
  fi
  # Com nova versao detectada, iniciar a atualizacao sem tela de confirmacao.
  local stage archive unpack candidate backup entry
  if ! command -v python3 >/dev/null 2>&1; then
    wait_enter_box 'ERRO' 'Python 3 necessario para validar o ZIP com seguranca.'
    return 0
  fi
  stage="$(mktemp -d)" || return 1
  archive="$stage/release.zip"
  unpack="$stage/unpack"
  mkdir -p "$unpack"
  printf '\n  Baixando atualizacao do GitHub...\n'
  if ! curl --fail --location --silent --show-error --connect-timeout 10 --max-time 120 \
      "https://codeload.github.com/${GITHUB_USER}/${GITHUB_REPO}/zip/refs/heads/${GITHUB_BRANCH}" -o "$archive" ||
      ! python3 - "$archive" "$unpack" <<'PYZIP'
import os, pathlib, sys, stat, zipfile
zip_path, target = sys.argv[1:]
with zipfile.ZipFile(zip_path) as z:
    entries = z.infolist()
    if not entries or len(entries) > 300 or sum(x.file_size for x in entries) > 20 * 1024 * 1024:
        raise ValueError('ZIP muito grande ou vazio')
    roots = set()
    seen = set()
    for info in entries:
        name = info.filename
        p = pathlib.PurePosixPath(name)
        if name.startswith('/') or '\\' in name or any(x in ('', '.', '..') for x in name.rstrip('/').split('/')) or (len(p.parts) < 2 and not info.is_dir()):
            raise ValueError('Caminho inseguro')
        if stat.S_IFMT(info.external_attr >> 16) == stat.S_IFLNK:
            raise ValueError('Link simbolico nao permitido')
        if name.rstrip('/') in seen:
            raise ValueError('Entrada duplicada')
        seen.add(name.rstrip('/'))
        roots.add(p.parts[0])
    if len(roots) != 1:
        raise ValueError('Mais de uma raiz no pacote')
    z.extractall(target)
PYZIP
  then
    rm -rf -- "$stage"
    wait_enter_box 'ERRO' 'Nao foi possivel baixar ou validar a atualizacao.'
    return 0
  fi
  candidate="$(find "$unpack" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  if [[ -z "$candidate" || ! -f "$candidate/version" || ! -f "$candidate/titanvps.sh" || ! -f "$candidate/scripts/menu.sh" || ! -f "$candidate/scripts/operacoes.sh" || ! -f "$candidate/scripts/badvpn.sh" || ! -f "$candidate/scripts/formatar.sh" || ! -f "$candidate/scripts/atualizador.sh" || ! -f "$candidate/scripts/central_ssh.sh" || ! -f "$candidate/scripts/status.sh" ]]; then
    rm -rf -- "$stage"
    wait_enter_box 'ERRO' 'O repositorio nao contem a estrutura esperada.'
    return 0
  fi
  local package_version
  package_version="$(tr -d '\r\n' < "$candidate/version")"
  if [[ "$package_version" != "$REMOTE_VERSION" ]]; then
    rm -rf -- "$stage"
    wait_enter_box 'ERRO' 'Versao do pacote diferente da versao anunciada.'
    return 0
  fi
  local syntax_ok=1 syntax_file
  for syntax_file in "$candidate/titanvps.sh" "$candidate/scripts/"*.sh; do
    if ! bash -n "$syntax_file"; then syntax_ok=0; break; fi
  done
  if (( ! syntax_ok )); then
    rm -rf -- "$stage"
    wait_enter_box 'ERRO' 'Pacote com sintaxe Bash invalida.'
    return 0
  fi
  # Nao seguir links simbolicos na origem, nem copiar arquivo de configuracao remoto.
  for entry in "$candidate/titanvps.sh" "$candidate/version" "$candidate/scripts/"*.sh; do
    if [[ -L "$entry" || ! -f "$entry" ]]; then
      rm -rf -- "$stage"
      wait_enter_box 'ERRO' 'Arquivo invalido no pacote remoto.'
      return 0
    fi
  done
  backup="$(mktemp -d "${TITANVPS_ROOT%/*}/titanvps-backup.XXXXXXXX")" || { rm -rf -- "$stage"; return 1; }
  if ! cp -a "$TITANVPS_ROOT/." "$backup/"; then
    rm -rf -- "$stage" "$backup"
    wait_enter_box 'ERRO' 'Falha ao gerar backup de seguranca.'
    return 0
  fi
  local failed=0
  # Configuracao local preservada; versoes antigas recebem a configuracao interna.
  mkdir -p "$TITANVPS_ROOT/.titanvps"
  if [[ ! -f "$TITANVPS_ROOT/.titanvps/github.conf" ]]; then
    if [[ -f "$TITANVPS_ROOT/github.conf" ]]; then
      cp -p "$TITANVPS_ROOT/github.conf" "$TITANVPS_ROOT/.titanvps/github.conf" || failed=1
    elif [[ -f "$candidate/.titanvps/github.conf" ]]; then
      install -m 0644 "$candidate/.titanvps/github.conf" "$TITANVPS_ROOT/.titanvps/github.conf" || failed=1
    fi
  fi
  local prior_manifest="$TITANVPS_ROOT/.managed-scripts"
  local new_manifest="$stage/managed-scripts"
  find "$candidate/scripts" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | LC_ALL=C sort > "$new_manifest"
  if [[ ! -s "$new_manifest" ]]; then
    rm -rf -- "$stage" "$backup"
    wait_enter_box 'ERRO' 'Nenhum modulo encontrado no pacote.'
    return 0
  fi
  install -m 0755 "$candidate/titanvps.sh" "$TITANVPS_ROOT/titanvps.sh" || failed=1
  if (( ! failed )); then
    for entry in "$candidate/scripts/"*.sh; do
      install -m 0755 "$entry" "$TITANVPS_ROOT/scripts/$(basename "$entry")" || { failed=1; break; }
    done
  fi
  if (( ! failed )); then
    install -m 0644 "$candidate/version" "$VERSION_FILE" || failed=1
    [[ -f "$candidate/README.md" ]] && install -m 0644 "$candidate/README.md" "$TITANVPS_ROOT/README.md" || true
  fi
  if (( failed )); then
    # Elimina arquivos novos antes de restaurar o estado anterior.
    while IFS= read -r filename; do
      if [[ ! -e "$backup/scripts/$filename" ]]; then rm -f -- "$TITANVPS_ROOT/scripts/$filename"; fi
    done < "$new_manifest"
    cp -a "$backup/." "$TITANVPS_ROOT/" || true
    rm -rf -- "$stage" "$backup"
    wait_enter_box 'ERRO' 'Falha ao aplicar pacote. Backup restaurado.'
    return 0
  fi
  if [[ -f "$prior_manifest" ]]; then
    while IFS= read -r filename; do
      [[ "$filename" =~ ^[a-zA-Z0-9_-]+\.sh$ ]] || continue
      if ! grep -Fxq -- "$filename" "$new_manifest"; then
        rm -f -- "$TITANVPS_ROOT/scripts/$filename"
      fi
    done < "$prior_manifest"
  fi
  install -m 0644 "$new_manifest" "$prior_manifest"
  # Remover apenas configuracao legada padrao, nunca a configuracao personalizada.
  if [[ -f "$TITANVPS_ROOT/github.conf" ]] && grep -q "GITHUB_USER='SEU_USUARIO'" "$TITANVPS_ROOT/github.conf"; then
    rm -f -- "$TITANVPS_ROOT/github.conf"
  fi
  # Registrar o comando global antes de considerar a atualizacao bem-sucedida.
  # Usar caminho real da instalacao (inclusive instalacoes anteriores).
  if (( EUID == 0 )); then
    local command_tmp='' launcher_target
    launcher_target="$TITANVPS_ROOT/titanvps.sh"
    if ! install -d -m 0755 /usr/local/bin; then
      failed=1
    else
      command_tmp="$(mktemp /usr/local/bin/.titanvps.XXXXXXXX)" || failed=1
      if (( ! failed )); then
        if ! printf '#!/usr/bin/env bash\nexec /bin/bash %q "$@"\n' "$launcher_target" > "$command_tmp" ||
           ! chmod 0755 "$command_tmp" ||
           ! mv -f -- "$command_tmp" /usr/local/bin/titanvps; then
          failed=1
        fi
      fi
    fi
    [[ -z "$command_tmp" ]] || rm -f -- "$command_tmp"
  else
    failed=1
  fi
  if (( failed )); then
    cp -a "$backup/." "$TITANVPS_ROOT/" || true
    rm -rf -- "$stage" "$backup"
    wait_enter_box 'ERRO' 'Falha ao registrar comando titanvps. Arquivos anteriores restaurados.'
    return 0
  fi
  # Reinicia o TITAN VPS pelo ponto de entrada oficial, na mesma sessao.
  # Nao exibe modal de sucesso, nao espera Enter e nao devolve o controle
  # ao processo antigo (que poderia sair para o shell).
  rm -rf -- "$stage" "$backup"
  hash -r 2>/dev/null || true
  exec /bin/bash "$TITANVPS_ROOT/titanvps.sh"
  # Se exec falhar, o shell ainda esta ativo: exibir falha real.
  printf '\nErro: nao foi possivel reabrir o TITAN VPS. Execute titanvps novamente.\n' >&2
  return 1
}
