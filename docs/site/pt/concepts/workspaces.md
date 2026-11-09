---
title: Workspaces e papéis
description: Onde uma equipe guarda seus fluxos, e o que cada papel pode fazer.
sidebar:
  order: 5
---

Um workspace é onde uma equipe guarda os fluxos, as execuções, as credenciais e as chaves de API. Ninguém de fora vê nada disso. O primeiro admin começa num chamado **Default**, e toda instalação feita antes de existirem workspaces tem os fluxos lá.

## Papéis

As pessoas entram num workspace com um papel. Cada papel faz tudo que o de cima dele na tabela faz.

| Papel | O que pode fazer |
| --- | --- |
| Viewer | Ver os fluxos, as execuções, os nomes das credenciais e os membros |
| Operator | Também rodar fluxos, como foram salvos |
| Editor | Também criar, mudar e apagar fluxos e credenciais, publicar e usar o agente |
| Admin | Também adicionar pessoas, mudar papéis, mandar convites e renomear o workspace |

Um workspace sempre tem pelo menos um admin.

**Admins do sistema** cuidam da instância. Eles são admins em todo workspace, e só eles criam e apagam workspaces, gerenciam usuários, configuram a página AI e o Terminal, e compartilham credenciais com todos os workspaces.

## Grupos de fluxos

Na página **Flows**, **New group** separa os fluxos, como *Vendas* ou *Cobrança*. Mova um fluxo pelo botão de pasta da linha dele, ou arraste ele para outro grupo. Um grupo recolhe pela seta ao lado do nome, e o lápis renomeia. Apagar um grupo mantém os fluxos dele: eles voltam para **No group**.

Os grupos só organizam a página: um fluxo roda igual em qualquer um deles. Todos no workspace veem os grupos, e editores para cima mudam eles.

## Trazendo pessoas

Abra **Members** na barra lateral:

- **Add someone** que já tem conta, pelo email ou nome de usuário.
- **Invite by link** alguém novo. O link cria a conta e traz a pessoa com o papel escolhido. Funciona uma vez, por 7 dias.

## Credenciais

Uma credencial pertence ao workspace dela, e só os fluxos dele podem usar. Dois workspaces podem ter, cada um, uma credencial com o mesmo nome.

Um admin do sistema também pode **compartilhar uma credencial com todos os workspaces**, como a chave do provedor de IA da empresa. Um fluxo procura o nome primeiro no próprio workspace, depois entre as compartilhadas. Os padrões da página AI usam credenciais compartilhadas, já que valem para a instância inteira.

## Chaves de API e apps

Uma chave de API pertence a você e ao workspace em que você criou. Ela só alcança aquele workspace, e nunca faz mais do que seu papel lá permite: se seu papel diminui, a chave também, e se você sai, ela para de funcionar. Os admins do workspace veem e revogam todas as chaves dele.

Quando um app como o Treadle entra pelo navegador, você escolhe o workspace que ele recebe.
