<h1 align="center">VideoGuardBypasser</h1>

<p align="center">
    <a href="https://discord.com"><img src="https://img.shields.io/badge/Discord-242629?logo=discord" alt="Discord"/></a>
    <a href="https://vencord.dev"><img src="https://img.shields.io/badge/Vencord-242629?logo=vencord" alt="Vencord"/></a>
</p>

<p align="center"><a href="/docs/README.en.md">English</a> · <strong>Português (Brasil)</strong></p>

Esse plugin permite que usuários do Discord consigam reestabelecer os recursos Go Live e chat de vídeo no Brasil<sup>[∗](https://discord.com/blog/a-letter-to-the-discord-community-in-brazil)</sup>. Para isso ele explora uma pequena vulnerabilidade na implementação de política de restrição por localização implementada pelo Discord.

> [!NOTE]
> Esse repositório tem o intuito puramente educativo.

<p align="center"><a href="#como-funciona-técnico">Como funciona (técnico)</a> · <a href="#instalação-vencord">Instalação</a> · <a href="#configurações">Configurações</a></p>

## Como funciona (técnico)

Esse repositório consiste em um plugin de [Vencord](https://vencord.dev/) (modificador de cliente Discord) que altera algumas características do cliente ([Discord Desktop](https://discord.com/download), [Vesktop](https://vesktop.dev/) ou [Navegador](https://discord.com/app)) permitindo ultrapassar as barreiras impostas. A barreira é composta por duas partes:

### Lado cliente (client-side)

Esse lado é o código executado no nosso computador e é responsável pela interação entre o usuário e o servidor. Como ele é executado localmente, ele é facilmente modificável, e tanto por conta disso existem inúmeras modificações criadas por usuários para incrementá-lo com diversas funcionalidades novas, como o próprio Vencord faz.

Nisso, a barreira imposta pelo Discord em seu cliente é uma simples "chave" (`2026-08-video-guard`<sup>[∗](https://github.com/EduardoVasconceloss/StreamFix/blob/4ab98977fa15e6c841106ef40b89c5034938a02d/streamFix/tunnel/trava.ts#L24)</sup>) escondida que define como o Discord se comportará com base em seu valor, que é definido ao inicializar o aplicativo baseado no seu endereço IP. Se o valor da chave for `-1`, o Discord se comportará como se você não se aplicasse à restrição criada por eles e sua interface se manterá sem bloqueios, mas caso o valor da chave for diferente a interface bloqueará visualmente o botão de ligar a câmera e compartilhar a tela e também esconderá se outras pessoas estiverem compartilhando a tela também.

Então, para circunvir isso o plugin simplesmente altera o valor dessa chave forçadamente para `-1`, se livrando do bloqueio visual implementado de forma irrastreável<sup>[∗](https://github.com/caiostoduto/VideoGuardBypasser/blob/90ddcd6b4798dc61a136e789bb6d8c4dfb911cca/vencord/index.ts#L27)</sup>.

### Lado servidor (server-side)

Esse lado são os servidores do Discord e obviamente não é possível modificar o código que está rodando neles.

Quando você interage para entrar numa ligação (ou clica para assistir uma tela) pelo Discord, o seu cliente (aplicativo) faz uma troca de mensagens (WebSocket Secure) para o servidor de mídia ao qual você deseja fazer conexão (`*discord.media`) solicitando para estabelecer a conexão WebRTC (protocolo de ligação usado pelo Discord) com os outros pares. Enquanto o cliente e o servidor fazem essa troca de mensagens o cliente estabelece uma conexão com o Interactive Connectivity Establishment (ICE), que por sua vez retorna para o cliente qual seu endereço IPv4 público. Por fim, esse endereço de IP é enviado pelo cliente para o servidor de mídia na troca de mensagens, e o servidor por sua vez recebe esse endereço IP e, por meio dele, infere sua localização e, se necessário, aplica suas políticas de restrição por localização para não permitir que você consiga ver a transmissão de outras pessoas, e nem que as outras pessoas consigam ver sua transmissão.

Esse sistema possui uma vulnerabilidade muito conhecida<sup>[∗](https://cwe.mitre.org/data/definitions/20.html)</sup>: nunca se deve confiar em dados enviados pelo cliente sem validá-los. O motivo é que, como você viu anteriormente na seção anterior [Lado servidor (server-side)](#lado-cliente-client-side) o usuário pode modificar o comportamento cliente, incluindo a sua comunicação com o servidor.

Então, para circunvir a restrição feita pelo servidor de mídia, o plugin intercepta a mensagem que o cliente manda contendo o seu endereço IP e o altera o conteúdo da mensagem para conter um endereço diferente do seu que não sofre da política de restrição<sup>[∗](https://github.com/caiostoduto/VideoGuardBypasser/blob/90ddcd6b4798dc61a136e789bb6d8c4dfb911cca/vencord/index.ts#L117)</sup>, já que o servidor não o valida corretamente.

## Instalação (Vencord)

> [!WARNING]
> O uso desse plugin pode infringir os [Termos de Serviço do Discord](https://discord.com/terms). Use por sua conta e risco.

### Script automatizado

Por conta da arquitetura do Vencord, a instalação de um plugin customizado não é tão simples, então para simplificar o processo de instalação foi criado um script interativo que automatiza todos os passos do processo.

<details closed>
<summary>O que o script faz</summary>

1. Verifica se os pré-requisitos estão instalados
2. (Windows) Instala `git` via `winget` caso o usuário não o tenha instalado
3. Instala Node.js e pnpm localmente caso necessário (se não está instalado ou desatualizado)
4. Baixa o plugin
5. Compila o Vencord com o plugin
6. (Discord Desktop) Injeta o Vencord no Discord
</details>

#### Windows (PowerShell)

Abra uma janela do PowerShell e execute o comando:

```powershell
irm https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1 | iex
```

Depois de instalar. Caso a instalação tenha sido feita no Discord Desktop, talvez você precise executar o comando novamente após uma atualização do Discord.<sup>[∗](https://www.reddit.com/r/VencordHelp/comments/1w44ddj/issues_after_every_discord_update/)</sup>.

<details closed>
<summary>Caso queira especificar o local de instalação do Vencord</summary>

```powershell
$installer = irm 'https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.ps1'
& ([scriptblock]::Create($installer)) -VencordDir "$HOME\Vencord"
```
</details>


#### Linux/MacOS

Pré-requisitos: `git` e `curl` ou `wget`

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh | bash
```

Depois de instalar. Caso a instalação tenha sido feita no Discord Desktop, talvez você precise executar o comando novamente após uma atualização do Discord<sup>[∗](https://www.reddit.com/r/VencordHelp/comments/1w44ddj/issues_after_every_discord_update/)</sup>.

<details closed>
<summary>Caso queira especificar o local de instalação do Vencord</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/install.sh \
  | bash -s -- --vencord-dir "$HOME/Vencord"
```
</details>

### Manualmente

Este é um _userplugin_ do [Vencord](https://vencord.dev) e precisa ser compilado como parte de um checkout do código-fonte dele. Antes de prosseguir, sugiro ler ao menos o aritgo [Building Vencord](https://docs.vencord.dev/installing/#building-vencord).

```sh
# Building Vencord (https://docs.vencord.dev/installing/#building-vencord)
git clone https://github.com/Vendicated/Vencord
cd Vencord
pnpm install --frozen-lockfile

# Custom Plugins (https://docs.vencord.dev/installing/custom-plugins/)
mkdir -p src/userplugins/videoGuardBypasser
curl https://raw.githubusercontent.com/caiostoduto/VideoGuardBypasser/main/vencord/index.ts -o src/userplugins/videoGuardBypasser/index.ts

pnpm build # ou pnpm buildWeb
pnpm inject # apenas se Discord Desktop
```

Depois de instalar. Caso a instalação tenha sido feita no Discord Desktop, talvez você precise executar o comando novamente após uma atualização do Discord<sup>[∗](https://www.reddit.com/r/VencordHelp/comments/1w44ddj/issues_after_every_discord_update/)</sup>.

## Configurações

| Configuração | Valor padrão | Descrição |
| --- | --- | --- |
| **Subnets** | `190.98.192.0/18` | Faixas IPv4 em notação CIDR, separadas por espaços. |
| **Port range** | `10000-20000` | Intervalo inclusivo no formato `mínimo-máximo`; ambas as portas devem estar entre 1024 e 65535. |
