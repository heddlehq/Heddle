---
title: Seu primeiro fluxo
description: Monte um fluxo que chama uma API, formata a resposta e mostra o resultado, depois rode e veja por dentro.
sidebar:
  order: 3
---

Em dez minutos você monta um fluxo que pergunta ao GitHub sobre um repositório, transforma a resposta numa frase e termina. No caminho, você roda, vê o que cada passo fez e publica.

Você precisa do Heddle rodando. Se ainda não está, veja [Instalação](/pt/docs/start/installation/).

## 1. Crie o fluxo

Abra **Flows** e aperte **New Flow**. O editor abre num canvas vazio, e o fluxo já está salvo: tudo que você mudar daqui em diante salva sozinho.

Para renomear, passe o mouse no nome lá em cima e clique no lápis. Chame de `GitHub stars`.

## 2. Adicione os nós

Os nós ficam na barra da esquerda. Arraste para o canvas, ou clique com o botão direito no canvas e escolha **Create Node**.

1. Adicione um **Start**. É onde a execução começa quando você aperta **Run**.
2. Adicione um **HTTP Request** e ligue a saída do **Start** na entrada dele: arraste do ponto à direita de um nó até o ponto à esquerda do outro.
3. Adicione um **Evaluate Code** depois dele.
4. Adicione um **Output** no fim.

## 3. Configure

Passe o mouse num nó e aperte a engrenagem para abrir a gaveta dele à direita. O que você digita vale na hora: não tem botão de salvar.

**HTTP Request**

| Campo | Valor |
| --- | --- |
| Method | `GET` |
| Endpoint URL | `https://api.github.com/repos/heddlehq/Heddle` |

**Evaluate Code**: escolha `python` como linguagem, aperte **Edit Code** e escreva:

```python
set_result(f"{result['full_name']} tem {result['stargazers_count']} estrelas")
```

`result` é o que o passo anterior deixou: aqui, o que o GitHub respondeu. [Dados numa execução](/pt/docs/concepts/context/) explica como os dados passam de um passo para o outro.

## 4. Rode

Aperte **Run Flow**, no canto superior direito. Cada nó mostra como foi o seu passo, e o **inspetor de execuções** abre embaixo do canvas.

Clique num passo no inspetor para ver o que ele recebeu e o que fez:

- No **HTTP Request**, **Output** mostra `result` com a resposta inteira do GitHub.
- No **Evaluate Code**, `result` agora é a frase.

Passe o mouse num valor e aperte **Copy as {{placeholder}}** para copiar o caminho até ele, como `{{result.stargazers_count}}`, pronto para colar no campo de outro nó.

## 5. Pare de chamar a API enquanto trabalha

Cada execução chama o GitHub de novo. Abra o passo do **HTTP Request** no inspetor e aperte **Pin output**: a partir de agora, as execuções do editor usam essa saída em vez de chamar a API, e o nó mostra um alfinete. Desafixe na gaveta do nó quando terminar. Execuções de produção nunca usam dados fixados.

## 6. Publique

O que você edita é o **rascunho**. Webhooks, agendamentos e a API rodam a **versão publicada**, e um fluxo que nunca foi publicado não roda sozinho. Aperte **Publish**, escreva uma nota como `Primeira versão` e confirme. O selo ao lado do nome agora diz **Live · v1**.

Se você mudar alguma coisa depois, o selo diz **Unpublished changes**: a produção continua rodando a v1 até você publicar de novo. Veja [Versões](/pt/docs/concepts/versions/).

## Ou importe pronto

Para pegar o fluxo pronto, baixe [first-flow.json](/docs/examples/first-flow.json), abra um fluxo novo, abra o menu **⋯** ao lado de **Publish** e aperte **Import from a file**.

## Próximos passos

- Dispare de fora: [Webhook para o Slack](/pt/docs/tutorials/webhook-to-slack/).
- Conheça o resto do editor: [O editor](/pt/docs/start/editor/).
