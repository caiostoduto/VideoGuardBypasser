# VideoGuardBypasser

[English](./README.md) | [Português (Brasil)](#videoguardbypasser)

> [!NOTE]
> O objetivo é demonstrar que os dados reportados pelo cliente estão sob controle do próprio cliente: o servidor não deve confiar em um endereço informado pelo usuário como prova de sua localização, nem usá-lo como único critério para decisões de política na camada de aplicação (OSI, camada 7).

Este é um proof of concept educacional para estudar dois fluxos do cliente do Discord relacionados a voz e compartilhamento de tela. Ele tem duas partes independentes:

- Ao iniciar, define a variante `-1` (desativada) para o experimento `2026-08-video-guard`. Esse experimento controla uma barreira na interface do cliente que pode impedir o compartilhamento de tela.
- Durante a conexão a um canal de voz, o cliente se comunica com um websocket `*.discord.media`, recebe o endereço e a porta de um RTC/SFU, conecta-se a esse RTC/SFU e, em seguida, informa seu endereço IPv4 ao websocket. Este plugin intercepta a resposta de `selectProtocol` e substitui o endereço e a porta por valores configurados antes que o cliente os informe.

> [!WARNING]
> Esta ferramenta pode ser contra os [Termos de Serviço do Discord](https://discord.com/terms). Use por sua conta e risco.

## Instalação

Este é um userplugin do Vencord e precisa ser compilado como parte de um checkout do código-fonte do Vencord; não pode ser compilado como um pacote TypeScript independente. Se você ainda não configurou um checkout do código-fonte, siga primeiro o guia [Building Vencord](https://docs.vencord.dev/installing/#building-vencord). As [instruções para plugins personalizados](https://docs.vencord.dev/installing/custom-plugins/) explicam em mais detalhes a estrutura de `src/userplugins`.

Copie a pasta `VideoGuardBypasser` deste repositório para `<checkout do Vencord>/src/userplugins/`, de forma que o ponto de entrada do plugin fique em `src/userplugins/VideoGuardBypasser/index.ts`. No checkout do Vencord, faça o build para a plataforma desejada:

```sh
pnpm build
```

Para a versão web, use `pnpm buildWeb`. Depois do build, reinicie o Discord e habilite **VideoGuardBypasser** nas configurações de plugins do Vencord.

## Configurações

- **Subnets**: faixas IPv4 em notação CIDR, separadas por espaços em branco. O plugin escolhe um endereço entre as faixas configuradas. Para prefixos até `/30`, os endereços de rede e broadcast são excluídos.
- **Port range**: intervalo inclusivo no formato `mínimo-máximo`. As portas devem estar entre 1 e 65535; os extremos podem ser informados em ordem inversa.
