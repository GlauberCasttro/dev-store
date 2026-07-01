---
description: Build+test global do projeto, resumo curto
---

Rode os comandos reais do `PROJECT_PROFILE.yaml` (stacks[0].build_cmd/test_cmd):

```
dotnet build --configuration Release --no-restore
dotnet test --no-build --no-restore --configuration Release
```

⚠ Verifique primeiro `PROJECT_PROFILE.yaml#stacks[0].verified` — hoje é `false` (SDK .NET
9.0.302 ausente no ambiente; só 8.0.125 instalado). Se ainda `false`, declare a degradação em
vez de reportar FAIL como se fosse bug de código. Resuma em ≤10 linhas: build OK/FAIL, testes
passados/falhos, warnings novos.
