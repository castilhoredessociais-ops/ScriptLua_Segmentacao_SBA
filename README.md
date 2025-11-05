Relatório Técnico – Sistema de Segmentação Inteligente de Clientes (IVR Dinâmico SBA)

Autor: José Castilho Tomás & Ivandro Neto
Projeto: Standard Bank Angola (SBA)
Data: Novembro de 2025

1. Introdução

Este projeto foi desenvolvido com o objetivo de aprimorar a experiência dos clientes do Standard Bank Angola (SBA) através de um sistema de atendimento telefónico inteligente e personalizado.
O sistema foi concebido para reconhecer automaticamente o cliente que liga para o banco e encaminhá-lo diretamente ao seu gestor ou à equipa responsável pelo seu segmento, reduzindo o tempo de espera e eliminando interações desnecessárias com menus complexos.

O projeto baseia-se numa integração entre FreeSWITCH, APIs REST, banco de dados PostgreSQL e serviço local de TTS (Text-to-Speech), garantindo flexibilidade, escalabilidade e total controlo sobre o fluxo das chamadas.

2. Objetivos do Sistema

Segmentar clientes de forma automática através da identificação do número (CID).

Encaminhar cada cliente diretamente ao seu gestor ou grupo de atendimento.

Garantir comunicação natural e imediata por meio de áudio TTS dinâmico.

Permitir expansão futura para novas operações no IVR (consultas, carregamentos, planos, etc.).

Evitar dependência de sistemas externos, assegurando execução local e independente.

3. Arquitetura e Tecnologias Utilizadas

Plataforma base: FreeSWITCH
Linguagem de script: Lua 5.2
Integrações externas: API REST (HTTP/JSON)
Base de dados: PostgreSQL
Serviço de voz: Google Cloud TTS (implementado via servidor Flask local)
Outros módulos:

dkjson – processamento JSON

socket.http e ltn12 – comunicações HTTP

ffmpeg – conversão e manipulação de áudio WAV

Estrutura de diretórios principais:

/usr/share/freeswitch/scripts/ivr_sba.lua        (script principal)
/opt/gcloud-tts-api/audio/                       (armazenamento de áudios TTS)
/var/lib/freeswitch/recordings/                  (áudios fixos e gravações)


Logs individuais por dia:
Cada execução gera um ficheiro de log separado com data, facilitando a auditoria e o acompanhamento de chamadas.

4. Funcionamento Técnico do Sistema

Identificação do Chamador (CID):
O número de telefone do cliente é capturado assim que a chamada entra.

Consulta ao Banco de Dados:
O script Lua faz uma requisição HTTP a uma API interna que consulta a base de dados PostgreSQL para identificar o cliente, o segmento e o gestor correspondente.

Segmentação Inteligente:
Com base no resultado da consulta, o sistema determina o destino:

Cliente Premium ou Corporate → Encaminhado diretamente ao gestor responsável.

Cliente Padrão ou Individual → Redirecionado para o IVR geral de atendimento.

Geração de Áudio TTS:
Uma mensagem personalizada é gerada localmente via Google TTS (em Flask), informando o nome do gestor ou saudando o cliente pelo nome.

Encaminhamento Automático (Bridge):
O FreeSWITCH estabelece a ponte SIP (sofia/gateway/...) para o destino correto, mantendo o Caller ID original e a rastreabilidade da sessão.

Gestão de Logs:
Cada chamada gera logs detalhados num ficheiro datado, permitindo análises posteriores de desempenho e diagnóstico.

5. Integração com Gestores de Clientes

A integração com os gestores é feita via API que retorna:

{
  "cliente": "Carlos M.",
  "segmento": "Premium",
  "gestor": "Ana Silva",
  "ramal_destino": "5772"
}


O sistema usa o campo “ramal_destino” para encaminhar automaticamente a chamada, garantindo que o cliente fale sempre com a pessoa certa — como se o sistema “já o conhecesse”.

6. Segmentação Inteligente de Chamadas

O IVR deixa de ser apenas um menu automático e torna-se um sistema de segmentação inteligente, capaz de:

Roteamento direto baseado em perfil de cliente.

Personalização imediata sem intervenção humana.

Priorização automática de clientes estratégicos.

Redução de tempo médio de atendimento (TMA).

Este conceito coloca o FreeSWITCH como um motor de decisão e relacionamento, e não apenas uma central telefónica.

7. Resultados e Benefícios Obtidos
Benefício	Descrição
Redução de tempo de espera	Clientes premium são encaminhados diretamente ao gestor.
Atendimento personalizado	Sistema reconhece o cliente e fala o seu nome.
Eficiência operacional	Menor carga de chamadas no IVR geral.
Escalabilidade	Código modular e integrado com APIs externas.
Controlo total local	Nenhuma dependência de serviços externos em nuvem.
8. Conclusões e Próximos Passos

O sistema de segmentação inteligente desenvolvido para o Standard Bank Angola representa uma evolução significativa no atendimento automatizado, unindo tecnologia, integração e personalização.

Próximos passos recomendados:

Adicionar autenticação via PIN para acessos sensíveis.

Implementar histórico de chamadas por cliente.

Introduzir um dashboard web para monitorização em tempo real.

Expandir o IVR com novos serviços (planos, transferências, etc.).

9. Autor e Créditos

Autor: José Castilho Tomás
Função: Analista e Arquiteto de Soluções em Telefonia e Integração
Contribuições:

Concepção da arquitetura técnica.

Desenvolvimento do script Lua e APIs associadas.

Implementação do TTS local e otimização do IVR.

Definição do modelo de segmentação inteligente por cliente.
