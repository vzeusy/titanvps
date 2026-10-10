# TITAN VPS

Gerenciador de servidores Linux, independente do painel Titan. Versão atual no arquivo `version`.

## Execução

```bash
sudo bash titanvps.sh
```

Menu: **A** Atualizar Script; **1** Atualizar Servidor; **2** Alterar Senha Root (entrada visível); **3** Formatar Servidor; **4** Central SSH; **0** Sair.

A Central SSH oferece `[1]` reservado, `[2]` DTProto, `[3]` SSHorizon (TG: @sshorizon_bot) e `[4]` BadVPN (submenu completo).

## GitHub

Edite somente `GITHUB_USER`, `GITHUB_REPO` e `GITHUB_BRANCH` em `github.conf`. Publique `titanvps.sh`, `version`, `github.conf` e `scripts/` na raiz do repositório. O arquivo `version` contém somente a versão, sem `v` (ex.: `0.0.1`). O script compara a versão local com a remota; cinza quando iguais, versão atual vermelha e remota verde quando a remota for superior.

A atualização baixa um arquivo ZIP do GitHub e só deve ser usada com repositórios confiáveis. A configuração local `github.conf` permanece intacta.

## Operações e riscos

- Atualizar Servidor: `apt-get update -y && apt-get upgrade -y && apt update && apt upgrade -y`.
- Alterar Senha Root: utiliza `chpasswd` local, não altera o SSH nem habilita acesso root remoto. A senha digitada **fica visível**; utilize somente em terminal privado e sem gravação.
- BadVPN: UDPGW 7300; multiporta 7300, 7400 e 3478; serviço systemd. Log `/var/log/titanvps-badvpn.log`; ajuste `/etc/sysctl.d/99-titanvps-badvpn.conf`. A compilação depende de internet e ferramentas de desenvolvimento.
- Formatar Servidor: executa o VPS Reinstaller de terceiros. **Reinicia automaticamente se o processo externo retornar código 0, mesmo se tiver sido cancelado internamente.** O programa externo não fornece sinal documentado confiável de que a reinstalação foi agendada. Mantenha backup externo e acesso ao console da VPS.
- DTProto e SSHorizon: scripts externos baixados, verificados quanto à sintaxe Bash e executados somente após confirmação; suas ações no servidor não foram auditadas nem testadas em VPS real.

## Testes

Execute `bash tests/test_static.sh` para checar sintaxe, versão, arquivos exigidos, nomenclatura e ausência de referências legadas. Este teste não altera o servidor.

As operações destrutivas não são executadas por testes automatizados. Teste instalações e reinícios em VPS descartável antes de usar em produção.

### Indicadores do menu

O cabeçalho apresenta, em até duas colunas por linha, somente serviços **ativos** conhecidos (BadVPN, DTProto e SSHorizon). A ausência de indicador significa que o serviço não foi identificado como ativo; nomes diferentes de unidades systemd podem exigir adaptação em `scripts/status.sh`. Os indicadores não afirmam que o software está ausente ou desinstalado.

### Proteções operacionais

- Instaladores externos verificam ferramentas mínimas antes do download e validam sintaxe Bash do arquivo recebido. Isso não garante a segurança do código remoto.
- Alterações de modo do BadVPN têm exclusão mútua (`flock`), backup local temporário das unidades e recuperação em caso de erro ou interrupção capturada.
- Outros instaladores de terceiros gerenciam seus próprios serviços e não podem ter rollback garantido pelo TITAN VPS.
- A opção Formatar Servidor continua reiniciando automaticamente se o reinstalador retornar código 0, mesmo se uma reinstalação não tiver sido efetivamente agendada.
