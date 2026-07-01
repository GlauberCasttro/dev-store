# HARNESS_USAGE — como operar o harness DevStore no dia a dia

Este é o guia de ONBOARDING (como usar). Para a visão diagnóstica (o que o harness é), ver
[SWARM.md](SWARM.md). Fluxo por tipo de demanda — uma seção por rota.

## Nova feature

1. Se o escopo/critério de aceite ainda não está claro, aciona `po` (refinamento, stories,
   acceptance criteria) antes de montar o brief.
2. Tech-lead verifica a tabela de triagem no `CLAUDE.md`: feature Tier A (contrato entre
   serviços, auth/JWT, schema com migration, MassTransit Saga, mudança em `DevStore.Core`)
   exige `architect` (ADR) + checkpoint humano ANTES de despachar dev-*. Feature comum vai
   direto ao `dev-*` dono da fronteira.
3. Tech-lead monta o brief (JSON, `allowed_paths` restrito, `context_inline` já extraído das
   fatias de domínio relevantes) e despacha.
4. Após `SUBMITTED`, despacha `verifier` (isolado, readonly) — nunca aceita sem `gate_report`.
5. `ACCEPTED` → atualiza `RESUME.md` imediatamente (nunca avançar 2+ tasks sem atualizar).

## Correção de bug

- Bug com arquivo:linha confirmado → `dev-*` direto → `verifier`. Não precisa de `po`/`architect`
  a menos que o fix cruze contrato entre serviços (ex.: corrigir o enum mismatch em
  `CreditCardPaymentFacade.cs:73` é só dev-billing; mudar o *shape* de `TransactionStatus`
  publicado no bus seria Tier A).
- Bug em área tocada por invariante (`DOMAIN_INVARIANTS.yaml` — SEC-1/2/3, OPS-1, BIZ-1/2/3):
  citar a invariante no brief e no `acceptance_criteria`, nunca deixar implícito.
- Auth/PII/pagamento envolvidos → gate `security` antes do `dev-*` (dev-billing/dev-identity/
  dev-customers).

## Dúvida de arquitetura / briefing do sistema

- Pergunta sobre fluxo entre fronteiras, trade-off de design, ou pedido de diagrama/visão geral
  → `architect`. Ele responde do `ARCHITECTURE_TREE.md` + `ORCHESTRATION_MAP.yaml` já
  pré-computados — nunca recusa alegando "só faço ADR" (anti-padrão conhecido).
- Pergunta puramente estrutural ("quem chama X", "onde está Y") → `/pesquisar-grafo` primeiro
  (consulta o grafo de símbolos), não grepar o repo do zero.
- Pergunta sobre integração externa (RabbitMQ, SQL Server, JWKS, gRPC) → `/mostrar-integracoes`.

## Retomar sessão

- Sempre `/carregar-contexto` no início de uma janela nova: lê `RESUME.md` → sprint ativa →
  brief da próxima task, nesta ordem, e PARA quando já tiver o suficiente (nunca "explore o
  projeto" do zero).
- Se havia task `IN_PROGRESS`, re-enuncia a âncora ao usuário e espera confirmação antes de
  despachar de novo.
- `RESUME.md` sem contexto suficiente para retomar sem pergunta extra é falha de protocolo —
  corrigir na hora, não na próxima sessão.

## Quando despachar direto vs via handshake

- Task trivial (1 arquivo, critério óbvio) → brief direto, sem `contract handshake` formal.
- Task não-trivial (ambígua, cross-fronteira, ou histórico de REJECTED no mesmo tipo) → acordar
  por escrito com o dev-* o que significa "pronto" ANTES da primeira linha de código.

## Fast-path para micro-correção

Typo, ajuste de log, rename local sem contrato externo: despacho direto ao `dev-*` dono, sem
`po`/`architect`, sempre que arquivo:linha já está confirmado e não cruza `DOMAIN_INVARIANTS.yaml`.

## Mapa de comandos por finalidade

| Preciso de... | Comando |
|---|---|
| Retomar sessão | `/carregar-contexto` |
| Nova sprint | `/nova-sprint` |
| Fechar sprint (100% COMMITTED) | `/fechar-sprint` |
| Fechar feature (relatório) | `/fechar-feature` |
| Saúde do harness (lint+doctor) | `/verificar-saude` |
| Métricas de sprint/agente | `/metricas` |
| Re-especializar stack | `/especializar` |
| Trocar de modelo | `/reaudit` |
| Consulta estrutural (grafo) | `/pesquisar-grafo` |
| Integrações externas | `/mostrar-integracoes` |
| Salvar sessão (curadoria de memória) | `/salvar-sessao` |
