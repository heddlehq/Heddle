---
title: Provedores de IA
description: Conecte Google, OpenAI, Anthropic ou xAI, e escolha o modelo que cada tipo de tarefa de IA usa.
sidebar:
  order: 6
---

Os nós de IA, o AI Agent e o chat do editor usam um modelo de um provedor que você conecta. O Heddle não manda nada para lugar nenhum até você conectar.

## O que cada provedor faz

| Provedor | Texto e chat | Ler imagens | Criar imagens | Transcrever áudio | Texto para fala |
| --- | --- | --- | --- | --- | --- |
| **Google** (Gemini, Nano Banana) | Sim | Sim | Sim | | |
| **OpenAI** (GPT, GPT Image, Whisper) | Sim | Sim | Sim | Sim | Sim |
| **Anthropic** (Claude) | Sim | Sim | | | |
| **xAI** (Grok) | Sim | Sim | Sim | | |

Pegue uma chave no provedor: [Google AI Studio](https://aistudio.google.com/apikey), [OpenAI](https://platform.openai.com/api-keys), [Anthropic Console](https://console.anthropic.com/settings/keys) ou [xAI Console](https://console.x.ai/).

## Conectar

1. Em **Credentials**, crie uma credencial de **AI provider**: escolha o provedor e cole a chave.
2. Em **AI → Models** (só admins do sistema), escolha uma credencial e um modelo para cada tipo de tarefa. Só aparecem os modelos que fazem aquela tarefa.

| Tarefa | Usada por |
| --- | --- |
| Texto e chat | AI Agent, Summarize, Translate, Classify, Extract Data e os chats |
| Ler imagens | Describe Image |
| Criar imagens | Generate Image e Edit Image |
| Transcrever áudio | Transcribe Audio |
| Texto para fala | Text to Speech |

## Por nó

Todo nó de IA tem os próprios campos **Credential** e **Model**. Deixe em branco para usar os padrões da página AI, ou escolha para aquele nó: um modelo barato para classificar, um forte para o agente. A credencial de um nó vem do workspace dele, e os padrões usam credenciais compartilhadas.

## Pelo ambiente

Sem nada disso, as tarefas de texto usam as variáveis `HEDDLE_LLM_PROVIDER`, `HEDDLE_LLM_MODEL` e `HEDDLE_LLM_API_KEY`, que o `heddle setup` pergunta na instalação. Veja [Configuração](/pt/docs/reference/configuration/#ia).

## Quanto custa

Cada chamada vai para o provedor com a sua chave, e o provedor cobra você. O inspetor mostra cada chamada que um AI Agent fez pelas ferramentas, e **Max steps** impede um agente de continuar para sempre.
