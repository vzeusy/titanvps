#!/usr/bin/env bash
set -Eeuo pipefail

# Executado do diretorio instalado ou diretamente por curl/process substitution.
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$BASE_DIR/scripts/menu.sh" ]]; then
  exec bash "$BASE_DIR/scripts/menu.sh" "$@"
fi

if (( EUID != 0 )); then
  echo 'Execute como root (sudo -i) antes de instalar o TITAN VPS.' >&2
  exit 1
fi
for cmd in curl python3 mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Dependencia ausente: $cmd" >&2
    exit 1
  fi
done

TARGET_DIR='/opt/titanvps'
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
ARCHIVE="$TEMP_DIR/source.zip"
echo 'Obtendo TITAN VPS do GitHub...'
curl -fSL --connect-timeout 10 --max-time 120 \
  'https://codeload.github.com/vzeusy/titanvps/zip/refs/heads/main' -o "$ARCHIVE"
python3 - "$ARCHIVE" "$TEMP_DIR" "$TARGET_DIR" <<'PYZIP'
import os, pathlib, shutil, stat, sys, tempfile, zipfile
archive, temp, dest = sys.argv[1:]
with zipfile.ZipFile(archive) as z:
    files=z.infolist()
    if len(files)>300 or sum(i.file_size for i in files)>20*1024*1024:
        raise SystemExit('Pacote invalido: tamanho excessivo')
    roots=set()
    for i in files:
        n=i.filename
        p=pathlib.PurePosixPath(n)
        if n.startswith('/') or '\\' in n or any(x in ('.','..','') for x in n.rstrip('/').split('/')) or len(p.parts)<2 or stat.S_IFMT(i.external_attr>>16)==stat.S_IFLNK:
            raise SystemExit('Pacote invalido: caminho inseguro')
        roots.add(p.parts[0])
    if len(roots)!=1:
        raise SystemExit('Pacote invalido: raiz inesperada')
    extract=pathlib.Path(temp)/'extracted'
    z.extractall(extract)
    source=extract/next(iter(roots))
    needed=['titanvps.sh','version','scripts/menu.sh','scripts/atualizador.sh','scripts/central_ssh.sh','scripts/operacoes.sh','scripts/formatar.sh','scripts/badvpn.sh','scripts/status.sh']
    if not all((source/f).is_file() for f in needed):
        raise SystemExit('Pacote sem arquivos obrigatorios')
    if (source/'version').read_text().strip() != '0.0.2' and not (source/'version').read_text().strip():
        raise SystemExit('Arquivo de versao invalido')
    destp=pathlib.Path(dest)
    destp.mkdir(parents=True, exist_ok=True)
    (destp/'scripts').mkdir(exist_ok=True)
    (destp/'.titanvps').mkdir(exist_ok=True)
    for f in ['titanvps.sh','version','README.md']:
        if (source/f).is_file():
            shutil.copy2(source/f,destp/f)
    for f in (source/'scripts').glob('*.sh'):
        shutil.copy2(f,destp/'scripts'/f.name)
    config=source/'.titanvps/github.conf'
    if config.is_file() and not (destp/'.titanvps/github.conf').exists():
        shutil.copy2(config,destp/'.titanvps/github.conf')
    for f in [destp/'titanvps.sh',*(destp/'scripts').glob('*.sh')]:
        f.chmod(0o755)
PYZIP
bash -n "$TARGET_DIR/titanvps.sh"
for script in "$TARGET_DIR"/scripts/*.sh; do bash -n "$script"; done
echo 'TITAN VPS instalado. Abrindo menu...'
exec bash "$TARGET_DIR/scripts/menu.sh" "$@"
