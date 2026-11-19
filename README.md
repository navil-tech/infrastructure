# Navil infrastructure

AWS resources and host deployment for the [marketing website](https://github.com/navil-tech/marketing-website).
The site's Dockerfile, environment variables and local development are described in its own README.

- `terraform/`: ECR repository, GitHub OIDC role for CI, EC2 host with Elastic IP, S3 bucket for database backups.
- `deploy/`: docker compose, nginx config and backup script that run on the host.

## Terraform

Account `470639361212`, region `us-east-1`, AWS CLI profile `yan428`. State lives in the S3 bucket `navil-tfstate-470639361212`.

```bash
cd terraform
cp terraform.example.tfvars terraform.tfvars   # set the AWS CLI profile and the path to your public ssh key
terraform init
terraform plan
terraform apply
```

Outputs: `elastic_ip` (the host), `ecr_repository_url`, `ci_role_arn`. DNS stays in Wix: the A records for `navil.co.il` and `www.navil.co.il` point at `elastic_ip`.

## Images and releases

CI in the site repository builds one image per push and pushes it to ECR `navil/marketing-website` through the OIDC role. Tags are immutable.

- Push to `dev`: image `dev-<sha7>`. ECR keeps the 5 most recent `dev-*` images.
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

### Telegram notifications

The site builds a Telegram message for every saved lead. To have it delivered, create a bot with @BotFather, add it to the chat that should receive the messages and set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `~/deploy/.env`, then `docker compose up -d`. For a group with topics also set `TELEGRAM_THREAD_ID` to the topic number, the middle part of a message link `t.me/c/<group>/<topic>/<message>`; without it the message goes to the general topic. With empty values the messages are stored in the database and not sent.

### Access log

nginx writes one JSON line per request to `/var/log/nginx/navil.access.log` (`log_format navil_json` in `deploy/nginx.conf`) and passes its request id to the site in `X-Request-Id`. The site stores this id in its events, so a line of the access log can be matched with the event it produced. The log is the independent record used to check the event model on real traffic. `time` is the moment the response was written, in seconds with milliseconds; the request arrived at `time − requestTime`.

certbot edits the server block on the host, so do not overwrite the host file with `deploy/nginx.conf`: add the `log_format` block above the server blocks, and the `access_log` and `X-Request-Id` lines to the server block that proxies to the site. Then `sudo nginx -t && sudo systemctl reload nginx`.

### Database access

Postgres listens only on `127.0.0.1:5432` of the host; the security group does not open the port. From a laptop, open an ssh tunnel and point a client at `localhost:5433` with the user and password from `deploy/.env` on the host:

```bash
ssh -N -L 5433:127.0.0.1:5432 ubuntu@<elastic_ip>
```

Or on the host itself:

```bash
cd ~/deploy
docker compose exec postgres psql -U "$POSTGRES_USER" "$POSTGRES_DB"
```

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
