# Navil infrastructure

AWS resources and host deployment for the [marketing website](https://github.com/navil-tech/marketing-website).
The site's Dockerfile, environment variables and local development are described in its own README.

- `terraform/`: ECR repository, GitHub OIDC role for CI, EC2 host with Elastic IP, S3 bucket for database backups.
- `deploy/`: docker compose, nginx config and backup script that run on the host.

## Terraform

Account `470639361212`, region `us-east-1`, AWS CLI profile `yan428`. State lives in the S3 bucket `navil-tfstate-470639361212`.

```bash
cd terraform
cp terraform.example.tfvars terraform.tfvars   # set the path to your public ssh key
terraform init
terraform plan
terraform apply
```

Outputs: `elastic_ip` (the host), `ecr_repository_url`, `ci_role_arn`. DNS stays in Wix: the A records for `navil.co.il` and `www.navil.co.il` point at `elastic_ip`.

## Images and releases

CI in the site repository builds one image per push and pushes it to ECR `navil/marketing-website` through the OIDC role. Tags are immutable.

- Push to `dev`: image `dev-<sha7>`. ECR keeps the 10 most recent `dev-*` images.
- Merge to `main`: semantic-release reads the conventional commits since the last release, bumps the version (`feat` is minor, everything else is patch), writes `CHANGELOG.md`, tags `vX.Y.Z` and pushes the image `X.Y.Z`. Release images are never expired.

## Deploying a tag on the host

```bash
ssh ubuntu@<elastic_ip>
cd ~/deploy
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 470639361212.dkr.ecr.us-east-1.amazonaws.com
sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=<tag>/' .env
docker compose up -d
docker compose logs app          # expect "All migrations have been successfully applied" and "Ready"
docker image prune -f            # drop images of previous tags
```

The container applies pending migrations before starting the site. `grep IMAGE_TAG .env` shows what is deployed. nginx on the host terminates TLS for `navil.co.il` and proxies to `127.0.0.1:3000`; certbot renews the certificate on its own.

## Backups

`deploy/backup.sh` runs from cron at 03:00 UTC on the host: `pg_dump` of the site database, gzipped, uploaded to the S3 bucket `navil-db-backups-470639361212` under the fixed key `navil.sql.gz`. The bucket is versioned and keeps the current copy plus the 9 previous ones. The host can only write to the bucket; reading needs the `yan428` profile.

Restore a copy from your laptop:

```bash
aws s3api list-object-versions --bucket navil-db-backups-470639361212 --prefix navil.sql.gz --profile yan428 \
  --query 'Versions[].[LastModified,VersionId]' --output table
aws s3api get-object --bucket navil-db-backups-470639361212 --key navil.sql.gz --version-id <id> --profile yan428 navil.sql.gz
scp navil.sql.gz ubuntu@<elastic_ip>:~/
```

Then on the host, into an empty database:

```bash
cd ~/deploy && set -a && source .env && set +a
docker compose stop app
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE \"$POSTGRES_DB\";" -c "CREATE DATABASE \"$POSTGRES_DB\";"
gunzip -c ~/navil.sql.gz | docker compose exec -T postgres psql -U "$POSTGRES_USER" "$POSTGRES_DB"
docker compose start app
```
