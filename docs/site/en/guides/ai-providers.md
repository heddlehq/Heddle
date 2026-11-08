---
title: AI providers
description: Connect Google, OpenAI, Anthropic or xAI, and pick the model each kind of AI task uses.
sidebar:
  order: 6
---

The AI nodes, the AI Agent and the chat in the editor all use a model from a provider you connect. Heddle sends nothing anywhere until you do.

## What each provider does

| Provider | Text and chat | Reading images | Creating images | Transcribing audio | Text to speech |
| --- | --- | --- | --- | --- | --- |
| **Google** (Gemini, Nano Banana) | Yes | Yes | Yes | | |
| **OpenAI** (GPT, GPT Image, Whisper) | Yes | Yes | Yes | Yes | Yes |
| **Anthropic** (Claude) | Yes | Yes | | | |
| **xAI** (Grok) | Yes | Yes | Yes | | |

Get a key from the provider: [Google AI Studio](https://aistudio.google.com/apikey), [OpenAI](https://platform.openai.com/api-keys), [Anthropic Console](https://console.anthropic.com/settings/keys) or [xAI Console](https://console.x.ai/).

## Connect one

1. In **Credentials**, create an **AI provider** credential: pick the provider and paste the key.
2. In **AI → Models** (system admins only), pick a credential and a model for each kind of task. The models offered are only the ones that can do it.

| Task | Used by |
| --- | --- |
| Text and chat | AI Agent, Summarize, Translate, Classify, Extract Data and the chats |
| Reading images | Describe Image |
| Creating images | Generate Image and Edit Image |
| Transcribing audio | Transcribe Audio |
| Text to speech | Text to Speech |

## Per node

Every AI node has its own **Credential** and **Model** fields. Leave them blank to use the defaults of the AI page, or pick them for that node: a cheap model to classify, a strong one for the agent. A node's credential comes from its workspace, and the defaults name shared credentials.

## From the environment

Without any of this, text tasks use the `HEDDLE_LLM_PROVIDER`, `HEDDLE_LLM_MODEL` and `HEDDLE_LLM_API_KEY` variables, which `heddle setup` asks for when you install. See [Configuration](/docs/reference/configuration/#ai).

## What it costs

Each call goes to the provider with your key, and the provider bills you. The run inspector shows every call an AI Agent made through its tools, and **Max steps** keeps an agent from going on forever.
