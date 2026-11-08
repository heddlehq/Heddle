---
title: Instalação
description: Instale o Heddle no seu computador com um comando, num servidor com Docker, ou a partir do código.
sidebar:
  order: 2
---

## Instalação com uma linha

É o jeito mais fácil de testar o Heddle no seu computador. Não precisa de mais nada: o Postgres e tudo que o Heddle usa vêm no download.

No Linux e no macOS (Apple Silicon):
```bash
curl -fsSL https://heddlehq.github.io/website/install.sh | sh
```

No Windows 10 ou mais novo, no PowerShell:
```powershell
irm https://heddlehq.github.io/website/install.ps1 | iex
```

O instalador então pergunta o que você quer. **Instalação rápida** só pergunta se você também quer o Treadle e qual IA usar, e **Personalizar tudo** passa pela pasta, versão, porta, desempenho e como ele inicia. Sua chave de IA é conferida com o provedor antes de instalar qualquer coisa, e nada muda no seu computador até você confirmar.

O Heddle então inicia e abre no navegador, onde você cria a conta de admin.

- **Onde fica:** `~/.heddle`, ou `%LOCALAPPDATA%\Heddle` no Windows. Se a pasta do seu usuário do Windows tem acento no nome, fica em `%ProgramData%\Heddle`, porque o Postgres e o Python não carregam de uma pasta assim. Seus dados ficam na pasta `data` lá dentro, e suas configurações em `heddle.env`.
- **Pastas com acento:** no Linux e no macOS, uma pasta pessoal como `/home/joão` precisa de `HEDDLE_HOME` apontando para uma pasta sem acento.
- **Acesso pela rede:** esta instalação só atende no seu computador. Fluxos podem rodar código com as permissões da sua conta, então rode só os que você confia.
- **Python:** a primeira inicialização baixa o Python, o que precisa de internet.

Esta instalação é para uma pessoa num computador. Para um servidor, ou para dividir o Heddle com uma equipe, escolha Docker no instalador, ou veja [Docker](#instalação-docker) abaixo. Como root ou num Linux com musl, como o Alpine, Docker é a opção que o instalador oferece.

### Instalar só o Treadle

O [Treadle](https://github.com/heddlehq/Treadle) é o editor no terminal. Para instalar só ele, numa máquina que se conecta a um Heddle rodando em outro lugar:

```bash
curl -fsSL https://heddlehq.github.io/website/install.sh | sh -s -- --treadle
```

```powershell
& ([scriptblock]::Create((irm https://heddlehq.github.io/website/install.ps1))) --treadle
```

Ele pede o servidor e uma chave de API, confere, e o Treadle abre já conectado. Deixe em branco para entrar pelo navegador quando abrir.

### Instalar sem perguntas

Sem um terminal, ou com `--yes`, nada é perguntado e o que não foi passado fica no padrão. Toda pergunta tem uma opção, e `heddle install --help` lista todas:

```bash
curl -fsSL https://heddlehq.github.io/website/install.sh | \
  HEDDLE_LLM_API_KEY=sk-ant-... sh -s -- --yes --with-treadle --port 4100 \
  --llm-provider anthropic --llm-model claude-sonnet-5-5
```

Prefira a variável `HEDDLE_LLM_API_KEY` a `--llm-key`, que aparece na lista de processos.

### O comando `heddle`

| Comando | O que faz |
| --- | --- |
| `heddle` ou `heddle start` | Inicia o Heddle neste terminal. `Ctrl+C` para. |
| `heddle start -d` | Inicia em segundo plano. |
| `heddle stop` | Para o Heddle e o banco, onde quer que tenha sido iniciado. |
| `heddle restart` | Para e inicia de novo, em segundo plano. |
| `heddle status` | Mostra o que está rodando e como está configurado. Aceita `--json`. |
| `heddle logs -f` | Acompanha os logs. `--db` mostra os do banco. |
| `heddle open` | Abre o Heddle no navegador. |
| `heddle setup` | Muda a IA, passo a passo. |
| `heddle config` | Lista as configurações. `set`, `get` e `unset` mudam. |
| `heddle autostart on` | Inicia o Heddle junto com o computador. Precisa de systemd. |
| `heddle doctor` | Confere se está tudo em ordem, inclusive sua chave de IA. |
| `heddle update` | Atualiza o Heddle, o Treadle e este comando. `--check` só olha. |
| `heddle backup` | Copia seus dados. `list` mostra as cópias, `restore` volta uma. |
| `heddle uninstall` | Remove o Heddle. `--keep-data` mantém seus dados. |

- **Atualizar:** `heddle update`, ou rode o comando de instalação de novo. Seus dados ficam, e uma cópia vai antes para a pasta `backups`, que guarda as três últimas. Se uma versão nova precisar de um Postgres que seus dados não suportam, ela para sem mudar nada.
- **Backup:** `heddle backup` para o Heddle durante a cópia e inicia de novo depois. `heddle backup restore` move seus dados atuais para o lado em vez de apagar.
- **Configurações:** `heddle config set` aceita qualquer coisa do [`.env.example`](https://github.com/heddlehq/Heddle/blob/main/.env.example). Reinicie para a mudança valer. Veja [Configuração](/pt/docs/reference/configuration/).

---

## Instalação (Docker)

Rodar com Docker é o jeito mais rápido num servidor, sem se preocupar com dependências.

### 1. Inicie o Heddle
```bash
git clone https://github.com/heddlehq/heddle.git
cd heddle
docker compose up -d --build
```

Isso inicia a interface, um worker e o Postgres. O primeiro build leva alguns minutos.

### 2. Crie a conta de admin
Acesse [`localhost:4000`](http://localhost:4000). A primeira visita pede para criar a conta de admin, que começa num workspace chamado Default. Para trazer sua equipe, veja [Workspaces e papéis](/pt/docs/concepts/workspaces/).

De outra máquina, use o endereço deste computador, como `http://192.168.1.50:4000`.

### 3. Configurações opcionais
Nada mais é obrigatório. Para mudar um padrão, copie `.env.example` para `.env` e edite:

- `HEDDLE_PORT` é a porta publicada nesta máquina, quando a `4000` está ocupada.
- `PHX_HOST` é o seu domínio público, só quando o Heddle fica atrás de HTTPS. Ele liga o redirecionamento para HTTPS, então seu proxy precisa mandar `X-Forwarded-Proto`.
- `SECRET_KEY_BASE` é gerado na primeira inicialização e guardado no volume `heddle_data`.

Para rodar tudo num único serviço:
```bash
docker compose --profile all up -d --build db all
```

### 4. Rodar sem Compose
Gere a imagem e aponte para o seu Postgres. `all` é o modo padrão. Passe `ui` ou `worker` para iniciar só um deles.

```bash
docker build -t heddle .

docker run --rm -p 4000:4000 \
  --env-file .env \
  -e DATABASE_URL=ecto://USER:PASS@HOST/heddle \
  heddle
```

Monte um volume em `/app/data`, ou defina `SECRET_KEY_BASE`, para as pessoas continuarem logadas depois de reiniciar.

### 5. Usar o banco a partir do código
Para rodar `mix phx.server` com o banco do Compose, publique ele nesta máquina:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d db
```

### 6. Concorrência e pools

A configuração padrão do Docker separa os principais ajustes de escala:

- `UI_POOL_SIZE=10`
- `WORKER_POOL_SIZE=10`
- `OBAN_EXECUTIONS_CONCURRENCY=50`
- `OBAN_DEFAULT_CONCURRENCY=2`
- `OBAN_RESCUE_AFTER_MINUTES=60`

Aumente as réplicas de worker com cuidado e ajuste esses valores junto com os limites do seu Postgres.

`OBAN_RESCUE_AFTER_MINUTES` é quanto tempo uma execução pode durar antes de o Heddle achar que o worker dela morreu e começar de novo do início. Deixe maior que o seu fluxo mais longo, ou um fluxo que ainda está rodando começa duas vezes.

### 7. Credenciais

A página **Credentials** guarda o que nós como Slack, S3 e FTP precisam para acessar outros serviços. Os valores são criptografados com uma chave derivada de `SECRET_KEY_BASE`, e os fluxos guardam só o nome da credencial. Veja [Credenciais](/pt/docs/guides/credentials/).

A interface e os workers precisam do mesmo segredo. Se ele mudar, todas as credenciais param de funcionar e precisam ser cadastradas de novo, então faça backup dele junto com os dados.

### 8. Modo só API

A interface pode rodar como um gateway HTTP, sem o editor:

```bash
HEDDLE_UI_MODE=api
```

Nesse modo, o Heddle inicia só a API:

- as rotas `/api/*` continuam disponíveis;
- os webhooks continuam disponíveis;
- as rotas do LiveView ficam desligadas;
- os arquivos da interface não são servidos;
- `/live` não é registrado.

Com Docker:

```bash
docker run --rm -p 4000:4000 \
  --env-file .env \
  -e DATABASE_URL=ecto://USER:PASS@HOST/heddle \
  -e HEDDLE_UI_MODE=api \
  heddle ui
```

---

## Requisitos para rodar a partir do código

- **Elixir** ~> 1.15
- **Erlang/OTP** 26+
- **PostgreSQL**
- **Node.js** (para os assets)

## Instalação (código)

### 1. Clone o repositório
```bash
git clone https://github.com/heddlehq/heddle.git
cd heddle
```

### 2. Instale as dependências
Este comando instala as dependências do Elixir e do JavaScript da interface em `apps/heddle_ui/assets`, incluindo o Rete.js (com `npm`, ou `bun` se não houver), cria o banco e roda as migrations.
```bash
mix setup
```

### 3. Inicie a interface e o worker
Abra dois terminais.

No primeiro:
```bash
cd apps/heddle_ui
mix phx.server
```

No segundo:
```bash
cd apps/heddle_worker
mix run --no-halt
```

Agora acesse [`localhost:4000`](http://localhost:4000) no navegador.

A interface abre sem o worker, mas as execuções e os webhooks precisam dele rodando.

### 4. Conferir

Para ver se está tudo certo, rode os testes:
```bash
mix test
```

Para rodar em várias máquinas e escalar os workers, veja [Escala](/pt/docs/self-hosting/scaling/).
