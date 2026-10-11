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

Requisitos:
- git
- curl (ou wget)

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh | bash
```

#### Windows (PowerShell)

Execute este comando no PowerShell. Se o Git estiver ausente, o instalador oferece instalá-lo pelo `winget`; também é necessário ter `curl.exe` ou `wget.exe`.

```powershell
irm https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1 | iex
```

### Manualmente

Este é um userplugin do Vencord e precisa ser compilado como parte de um checkout do código-fonte do Vencord; não pode ser compilado como um pacote TypeScript independente. Se você ainda não configurou um checkout do código-fonte, siga primeiro o guia [Building Vencord](https://docs.vencord.dev/installing/#building-vencord). As [instruções para plugins personalizados](https://docs.vencord.dev/installing/custom-plugins/) explicam em mais detalhes a estrutura de `src/userplugins`.

```sh
git clone https://github.com/Vendicated/Vencord
cd Vencord
pnpm install --frozen-lockfile
pnpm inject
```

Copie o conteúdo da pasta `vencord` deste repositório para `<checkout do Vencord>/src/userplugins/videoGuardBypasser/`, de forma que o ponto de entrada do plugin fique em `src/userplugins/videoGuardBypasser/index.ts`. No checkout do Vencord, faça o build para a plataforma desejada:

```sh
mkdir src/userplugins/videoGuardBypasser
curl https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts -o src/userplugins/videoGuardBypasser/index.ts
pnpm build # ou `pnpm buildWeb` para versão web
```

Depois do build, reinicie o Discord e habilite **VideoGuardBypasser** nas configurações de plugins do Vencord.

## Configurações

| Configuração | Valor padrão | Descrição |
| --- | --- | --- |
| **Subnets** | `190.98.192.0/18` | Faixas IPv4 em notação CIDR, separadas por espaços. |
| **Port range** | `10000-20000` | Intervalo inclusivo no formato `mínimo-máximo`; ambas as portas devem estar entre 1024 e 65535. |
