---
title: O comando heddle
description: Instale, inicie, pare, atualize, faça backup e configure o Heddle pelo terminal.
sidebar:
  order: 3
---

O comando `heddle` vem com toda instalação. Ele instala o Heddle e o [Treadle](https://github.com/heddlehq/Treadle), roda os dois e cuida deles. Tudo que ele diz sai em inglês ou português, conforme o seu sistema.

## Rodando

| Comando | Faz |
| --- | --- |
| `heddle` ou `heddle start` | Inicia o Heddle neste terminal. `Ctrl+C` para. |
| `heddle start -d` | Inicia em segundo plano. |
| `heddle stop` | Para o Heddle e o banco, onde quer que tenha sido iniciado. |
| `heddle restart` | Para e inicia de novo, em segundo plano. |
| `heddle status` | O que está rodando e como está configurado. `--json` para scripts. |
| `heddle logs -f` | Acompanha os logs. `--db` mostra os do banco. |
| `heddle open` | Abre o Heddle no navegador. |
| `heddle version` | As versões instaladas. |

## Configurações

| Comando | Faz |
| --- | --- |
| `heddle config list` | Lista as configurações, com os segredos escondidos. |
| `heddle config get CHAVE` | Mostra uma. |
| `heddle config set CHAVE=VALOR...` | Muda. Reinicie para valer. |
| `heddle config unset CHAVE...` | Remove. |
| `heddle config path` | Onde fica o arquivo de configurações. |
| `heddle setup` | Muda a IA, passo a passo. |
| `heddle autostart on` / `off` | Inicia o Heddle junto com o computador. Precisa de systemd. |

As chaves são as [variáveis de ambiente](/pt/docs/reference/configuration/).

## Cuidando dele

| Comando | Faz |
| --- | --- |
| `heddle doctor` | Confere se está tudo em ordem, inclusive sua chave de IA. |
| `heddle update` | Atualiza o Heddle, o Treadle e ele mesmo. `--check` só olha. |
| `heddle backup` | Copia seus dados. O Heddle para durante a cópia e inicia de novo. |
| `heddle backup list` | Lista as cópias. |
| `heddle backup restore NOME` | Volta uma cópia, movendo os dados atuais para o lado. |
| `heddle uninstall` | Remove o Heddle. `--keep-data` mantém seus dados. |

`heddle update` faz um backup antes, e guarda os três últimos.

## Instalando

| Comando | Faz |
| --- | --- |
| `heddle install` | Instala o Heddle, perguntando o que você quer. |
| `heddle install --yes` | Instala com os padrões, sem perguntar nada. |
| `heddle install --help` | Todas as opções, uma por pergunta. |

Veja [Instalação](/pt/docs/start/installation/).
