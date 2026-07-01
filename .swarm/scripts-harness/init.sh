#!/usr/bin/env bash
# init.sh — sobe o ambiente de dev do DevStore. Comandos reais confirmados em
# README.md ("Getting Started") + docker/*.yml — nada inventado.
#
# Uso:
#   bash .swarm/scripts-harness/init.sh            # imagens prebuilt (mais rápido)
#   bash .swarm/scripts-harness/init.sh --build     # build local via Docker (não exige SDK no host)
#   bash .swarm/scripts-harness/init.sh --down       # derruba o ambiente
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-}"

case "$MODE" in
  --down)
    docker compose -f docker/docker-compose.yml down
    ;;
  --build)
    # build local (1 container de banco por serviço) — não depende do .NET SDK
    # do host: o build roda dentro da imagem Docker. Ver docker/docker-compose-local.yml.
    docker compose -f docker/docker-compose-local.yml up --build
    ;;
  "")
    # caminho padrão do README: imagens prebuilt do Docker Hub, mais rápido para
    # rodar sem esperar build. SDK .NET 9.0.302 (global.json) permanece
    # `verified:false` no host (não instalado) — não é necessário para este caminho.
    docker compose -f docker/docker-compose.yml up
    ;;
  *)
    echo "uso: $0 [--build|--down]" >&2
    exit 1
    ;;
esac
