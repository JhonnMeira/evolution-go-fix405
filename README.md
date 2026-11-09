# Evolution Go — correção do erro "Client outdated (405)"

Em **02/11/2026** o WhatsApp aposentou a versão de cliente `2.3000.1042386815`, que vem compilada
nas imagens `0.7.2`, `0.7.2-beta` e `latest` do [Evolution Go](https://github.com/evolution-foundation/evolution-go).
A partir daí o handshake é recusado com **405** e as instâncias param:

```
[Client ERROR] Client outdated (405) connect failure (client version: 2.3000.1042386815)
[Client/Socket ERROR] Error reading from websocket: failed to get reader: failed to read frame header: EOF
```

A instância **não conecta e nem chega a gerar o QR Code**. Não é sessão perdida, não é proxy e não é
o servidor — reiniciar, recriar a instância ou ler o QR **não resolvem**, e atualizar a imagem também
não, porque a correção ainda não foi publicada pelo projeto.

## Por quê

O Evolution Go busca a versão vigente do WhatsApp, mas grava só em `store.DeviceProps.Version` (o
rótulo da lista de aparelhos). O handshake usa `store.GetWAVersion()`, que continua com o valor
compilado — ninguém chama `store.SetWAVersion`. As variáveis `WHATSAPP_VERSION_MAJOR/MINOR/PATCH`
também não resolvem, pelo mesmo motivo.

A correção são **5 linhas** (é o [PR #227](https://github.com/evolution-foundation/evolution-go/pull/227)
do próprio projeto, ainda não mergeado). O melhor dela: passa a buscar a versão vigente **a cada
conexão**, então o próximo aposentamento de versão se resolve sozinho, sem recompilar. E **religa sem
QR** — as sessões antigas ficam intactas.

## Como usar

Na sua VPS (onde o Evolution Go roda em Docker), como **root** ou com **sudo**:

```bash
curl -fsSL https://raw.githubusercontent.com/JhonnMeira/evolution-go-fix405/main/corrigir-405.sh -o corrigir-405.sh
sudo bash corrigir-405.sh
```

Esse primeiro comando **só diagnostica** — acha o serviço, confere se é mesmo o 405 e mostra se a
máquina aguenta montar a imagem. Não altera nada.

Para aplicar a correção:

```bash
sudo bash corrigir-405.sh --corrigir
```

Ele clona a **mesma versão** que você já roda (para não trazer nenhuma outra mudança junto), aplica a
correção, monta uma imagem Docker e — depois de **pedir sua confirmação** — sobe no lugar da atual.
Nada é apagado, e o comando para voltar atrás é mostrado no fim.

- Se tiver mais de um serviço Evolution Go, rode com o nome:
  `sudo bash corrigir-405.sh --corrigir NOME_DO_SERVICO`
- Se você usa `docker compose` (e não Docker Swarm), o script monta a imagem e te mostra a linha
  exata para trocar no `docker-compose.yml` — a troca em si fica com você.

O build quer cerca de **2 GB de RAM** e **5 GB de disco livre**, e demora alguns minutos.

## Confirmando que pegou

Depois de aplicar, o log passa a mostrar, a cada conexão:

```
Applied store.SetWAVersion -> 2.3000.1052855845
```

As instâncias voltam sozinhas, sem QR. Se alguma continuar fora, é porque foi desconectada no celular
do dono — essa só volta com QR dele.

---

Mantido por **Jhon Meira — THENS Desenvolvimento de Sistemas** · [thens.com.br](https://www.thens.com.br)
