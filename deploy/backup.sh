#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
source .env
set +a

docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip \
  | aws s3 cp --region us-east-1 - s3://navil-db-backups-470639361212/navil.sql.gz
