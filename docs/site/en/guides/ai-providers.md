---
title: AI providers
description: Connect Google, OpenAI, Anthropic, xAI or any server that speaks the OpenAI API, and pick the model each kind of AI task uses.
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
| **OpenAI-compatible server** (Ollama, OpenRouter, Groq, LM Studio, vLLM…) | Yes | If the model does | | | |

Get a key from the provider: [Google AI Studio](https://aistudio.google.com/apikey), [OpenAI](https://platform.openai.com/api-keys), [Anthropic Console](https://console.anthropic.com/settings/keys) or [xAI Console](https://console.x.ai/).

## Any model, local or not

Any server that speaks the OpenAI API works: a model running on your machine through [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai), your own [vLLM](https://docs.vllm.ai), or a service like [OpenRouter](https://openrouter.ai), [Groq](https://groq.com) or [DeepSeek](https://platform.deepseek.com). Create an **AI provider** credential with **OpenAI-compatible server** as the provider, and:

- **Server address**: where its API is, ending in `/v1`, like `http://localhost:11434/v1` for Ollama. The field suggests the usual ones.
- **API key**: the key of the service. A local server usually needs none.
- **Model**: the one to use by default. Heddle lists the models the server has, so this only matters when it doesn't list them.

It does text and chat, and reads images when the model does. The AI Agent and the chats need a model that calls tools: Heddle says so when one doesn't, and you can pick another for them.

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

Every step that called a model keeps how many calls it made, their tokens and their price in US dollars. The run inspector shows it on the step and the total on the run, and the Executions page shows the total too. An AI Agent's step counts only its own calls: a tool it runs counts on its own step, so the total never counts a call twice. A model whose price Heddle doesn't know, like one on your own server, shows its tokens alone.
