<div align="right">

[English](/docs/README.en.md) · **Português (Brasil)**

</div>

# VideoGuardBypasser

> [!NOTE]
> O objetivo é demonstrar que os dados reportados pelo cliente estão sob controle do próprio cliente: o servidor não deve confiar em um endereço informado pelo usuário como prova de sua localização, nem usá-lo como único critério para decisões de política na camada de aplicação (OSI, camada 7).

Este é um proof of concept educacional para estudar dois fluxos do cliente do Discord relacionados a voz e compartilhamento de tela. Ele tem duas partes independentes:

- Ao iniciar, define a variante `-1` (desativada) para o experimento `2026-08-video-guard`. Esse experimento controla uma barreira na interface do cliente que pode impedir o compartilhamento de tela.
- Durante a conexão a um canal de voz, o cliente se comunica com um websocket `*.discord.media`, recebe o endereço e a porta de um RTC/SFU, conecta-se a esse RTC/SFU e, em seguida, informa seu endereço IPv4 ao websocket. Este plugin intercepta a resposta de `selectProtocol` e substitui o endereço e a porta por valores configurados antes que o cliente os informe. A política de localização do Discord trata o IPv4 reportado como o endereço do cliente e, por isso, considera a localização do endereço substituto em vez da localização real do cliente.

## Instalação (Vencord)

> [!WARNING]
> Esta ferramenta pode infringir os [Termos de Serviço do Discord](https://discord.com/terms). Use por sua conta e risco.

### Automaticamente

#### Linux/MacOS

Requisitos: `git` e `curl` ou `wget`.

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh | bash
```

Por padrão, o instalador usa `~/Vencord`. Passe opções por `bash -s --` para usar outro checkout ou idioma:

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh \
  | bash -s -- --vencord-dir "$HOME/src/Vencord" --lang pt
```

As opções aceitas são `--vencord-dir CAMINHO` e `--lang en|pt` (também aceitam o formato `--vencord-dir=CAMINHO` e `--lang=pt`). Se `--lang` for omitido, o idioma é detectado pela localidade do sistema.

#### Windows (PowerShell)

Execute em uma janela interativa do PowerShell. O Git é obrigatório; se estiver ausente, o instalador oferece instalá-lo pelo `winget`. `winget.exe` é necessário para essa opção. Também é preciso ter `curl.exe` ou `wget.exe`.

```powershell
irm https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1 | iex
```

O checkout padrão do Vencord fica em `$HOME\Vencord`. Para indicar outro caminho ou escolher o idioma, baixe e execute o script com parâmetros:

```powershell
$installer = irm 'https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1'
& ([scriptblock]::Create($installer)) -VencordDir "$HOME\src\Vencord" -Language pt
```

`-VencordDir` recebe o caminho do checkout e `-Language` aceita `en` ou `pt`. Se o PowerShell bloquear um arquivo `.ps1` salvo devido à política de execução, permita scripts apenas na janela atual com `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`; ao fechar a janela, a configuração é revertida.

#### O que o instalador automático faz

Ele clona o Vencord no caminho padrão (ou, após perguntar, atualiza o checkout existente), lê as versões necessárias do Node.js e do pnpm em `package.json`, instala o plugin e compila o destino escolhido. Primeiro, verifica se já há versões compatíveis do Node.js e do pnpm. Se algum estiver ausente ou desatualizado, pede confirmação antes de instalar localmente: usa uma versão LTS do Node.js que atenda ao requisito mínimo do Vencord (cerca de 100 MB instalado) e a versão do pnpm exigida pelo Vencord (cerca de 10 MB instalado). Esses programas ficam em `~/.local/share/vencord-installer/` no Linux/macOS ou `%LOCALAPPDATA%\vencord-installer\` no Windows e são adicionados ao `PATH` apenas durante a execução do instalador.

O instalador pergunta qual destino deve compilar. Para o aplicativo Discord, siga as instruções do injetor. Ao terminar, reinicie o Discord e habilite **VideoGuardBypasser** em **Configurações → Plugins → VideoGuardBypasser**. Para Vesktop e Web, ele mostra as instruções de build personalizado do Vencord.

### Manualmente

Este é um userplugin do Vencord e precisa ser compilado como parte de um checkout do código-fonte do Vencord; não pode ser compilado como um pacote TypeScript independente. Se você ainda não configurou um checkout do código-fonte, siga primeiro o guia [Building Vencord](https://docs.vencord.dev/installing/#building-vencord). As [instruções para plugins personalizados](https://docs.vencord.dev/installing/custom-plugins/) explicam em mais detalhes a estrutura de `src/userplugins`.

```sh
git clone https://github.com/Vendicated/Vencord
cd Vencord
pnpm install --frozen-lockfile
mkdir -p src/userplugins/videoGuardBypasser
curl https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts -o src/userplugins/videoGuardBypasser/index.ts
pnpm build
pnpm inject
```

Para uma build Web, use `pnpm buildWeb` no lugar de `pnpm build` e siga o guia de build personalizado para carregá-la no navegador. Depois de instalar a build do aplicativo Discord, reinicie o Discord e habilite **VideoGuardBypasser** em **Configurações → Plugins → VideoGuardBypasser**.

## Configurações

| Configuração | Valor padrão | Descrição |
| --- | --- | --- |
| **Subnets** | `190.98.192.0/18` | Faixas IPv4 em notação CIDR, separadas por espaços. |
| **Port range** | `10000-20000` | Intervalo inclusivo no formato `mínimo-máximo`; ambas as portas devem estar entre 1024 e 65535. |
