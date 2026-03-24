# ELK + Fleet Server template

This repository deploys a small self-managed stack with:

- Elasticsearch `9.1.2`
- Kibana `9.1.2`
- Fleet Server
- `waf-nginx`
- `dvwa` and `juiceshop` as optional demo targets

## Before you deploy

- This repo is better suited to Linux or WSL2 than plain Windows because Fleet Server bind-mounts `/var/run/docker.sock` and `/var/lib/docker/containers`.
- The repo does not include any TLS assets. You must create `./certs` before running `docker compose up`.
- Elasticsearch and Kibana are configured for HTTPS, so the `setup` container also needs access to the CA certificate.
- `up.sh` starts Fleet Server and the demo apps as well. Do not use it for the very first bootstrap if `.env` does not already contain the Fleet token and policy values.

## Required `certs/` files

The current compose files expect these files:

- `certs/ca.crt`
- `certs/elasticsearch.crt`
- `certs/elasticsearch.key`
- `certs/kibana.crt`
- `certs/kibana.key`
- `certs/fleet-server-cert.pem`
- `certs/fleet-server-key.pem`

You can generate a local CA and service certificates with `openssl` like this:

```bash
mkdir -p certs

openssl genrsa -out certs/ca.key 4096
openssl req -x509 -new -nodes \
  -key certs/ca.key \
  -sha256 -days 3650 \
  -out certs/ca.crt \
  -subj "/CN=elastic-local-ca"

make_cert() {
  local name="$1"
  local key_path="$2"
  local crt_path="$3"
  local san="$4"

  cat > "certs/${name}.ext" <<EOF
subjectAltName=${san}
extendedKeyUsage=serverAuth,clientAuth
EOF

  openssl req -new -nodes -newkey rsa:4096 \
    -keyout "${key_path}" \
    -out "certs/${name}.csr" \
    -subj "/CN=${name}"

  openssl x509 -req \
    -in "certs/${name}.csr" \
    -CA certs/ca.crt \
    -CAkey certs/ca.key \
    -CAcreateserial \
    -out "${crt_path}" \
    -days 825 \
    -sha256 \
    -extfile "certs/${name}.ext"

  rm -f "certs/${name}.csr" "certs/${name}.ext"
}

make_cert elasticsearch certs/elasticsearch.key certs/elasticsearch.crt \
  "DNS:elasticsearch,DNS:localhost,IP:127.0.0.1"

make_cert kibana certs/kibana.key certs/kibana.crt \
  "DNS:kibana,DNS:localhost,IP:127.0.0.1,DNS:<HOSTNAME>,IP:<HOST_IP>"

make_cert fleet-server certs/fleet-server-key.pem certs/fleet-server-cert.pem \
  "DNS:fleet-server,DNS:localhost,IP:127.0.0.1,DNS:<HOSTNAME>,IP:<HOST_IP>"
```

Notes:

- Replace `<HOSTNAME>` and `<HOST_IP>` with the real hostname/IP you will use to access Kibana and Fleet Server.
- The Elasticsearch certificate must include `DNS:elasticsearch` because Kibana and Fleet Server connect to Elasticsearch by container name.
- The Fleet Server certificate must match the address your Elastic Agents will use for `https://<host>:8220`.

## 1. Update `.env`

At minimum, change these values:

```env
ELASTIC_PASSWORD='change-this-password'
KIBANA_SYSTEM_PASSWORD='change-this-password'
LOGSTASH_INTERNAL_PASSWORD='change-this-password'

FLEET_SERVER_SERVICE_TOKEN=''
FLEET_SERVER_POLICY_ID=''
FLEET_ENROLLMENT_TOKEN=''
```

Notes:

- `ELASTIC_PASSWORD` and `KIBANA_SYSTEM_PASSWORD` are required.
- Leave `FLEET_SERVER_SERVICE_TOKEN` and `FLEET_SERVER_POLICY_ID` empty during the first bootstrap, then fill them in after Kibana is up.
- `FLEET_ENROLLMENT_TOKEN` is not required to start `fleet-server` in this repo, but you can store it here for later agent enrollment.

## 2. Bootstrap Elasticsearch and Kibana

For the first run, start only the core services:

```bash
docker compose up -d elasticsearch kibana
docker compose --profile setup up setup
```

The `setup` step sets passwords for `kibana_system` and the other internal users.

Quick checks:

- Elasticsearch: `https://localhost:9200`
- Kibana: `https://localhost:5601`

Log in to Kibana with:

- user: `elastic`
- password: the `ELASTIC_PASSWORD` value from `.env`

## 3. Configure Fleet in Kibana

Once Kibana is reachable:

1. Open `Management > Fleet > Settings`.
2. Set `Fleet Server hosts` to `https://<PUBLIC_HOST_OR_IP>:8220`.
3. Set `Outputs > Default output > Hosts` to `https://<PUBLIC_HOST_OR_IP>:9200`.
4. Create or select a `Fleet Server policy`, then copy the `policy id`.
5. Create a Fleet Server service token:

```bash
curl --cacert certs/ca.crt \
  -u "elastic:<ELASTIC_PASSWORD>" \
  -X POST \
  "https://localhost:9200/_security/service/elastic/fleet-server/credential/token/fleet-server-docker?pretty"
```

Use the returned `token.value`.

Then update `.env`:

```env
FLEET_SERVER_SERVICE_TOKEN='...token.value...'
FLEET_SERVER_POLICY_ID='...policy-id...'
FLEET_ENROLLMENT_TOKEN='...optional...'
```

If you want to enroll Elastic Agents on other machines, create an enrollment token in the Fleet UI and either store it in `.env` or use the enrollment command Kibana generates.

## 4. Start Fleet Server

After `.env` contains both `FLEET_SERVER_SERVICE_TOKEN` and `FLEET_SERVER_POLICY_ID`, start Fleet Server:

```bash
docker compose \
  -f docker-compose.yml \
  -f extensions/fleet/fleet-compose.yml \
  up -d fleet-server
```

Watch the logs with:

```bash
docker compose \
  -f docker-compose.yml \
  -f extensions/fleet/fleet-compose.yml \
  logs -f fleet-server
```

Fleet Server listens on port `8220`.

## 5. Start the full stack, if needed

If you also want the demo apps and WAF path:

```bash
./up.sh
```

That is equivalent to:

```bash
docker compose \
  -f docker-compose.yml \
  -f extensions/fleet/fleet-compose.yml \
  -f web/web-compose.yml \
  up -d
```

Default ports:

- Kibana: `5601`
- Elasticsearch: `9200`
- Fleet Server: `8220`
- DVWA through WAF: `8081`
- Juice Shop through WAF: `8082`

Note: `waf/nginx.conf` currently only routes `8081` and `8082`. Even though the container publishes `80` and `443`, the repo does not yet define a complete public HTTPS listener on those ports.

## Stop the stack

```bash
./down.sh
```

Or:

```bash
docker compose \
  -f docker-compose.yml \
  -f extensions/fleet/fleet-compose.yml \
  -f web/web-compose.yml \
  down
```

## Common issues

- `x509: certificate signed by unknown authority`: the CA is missing, wrong, or not provided to the enrolling agent.
- Browser certificate mismatch: the Kibana or Fleet Server certificate does not contain the hostname/IP you are using.
- `fleet-server` keeps restarting: `FLEET_SERVER_SERVICE_TOKEN` or `FLEET_SERVER_POLICY_ID` is empty or invalid.
- `setup` fails on first boot: check `certs/ca.crt`, `ELASTIC_PASSWORD`, and whether Elasticsearch has finished starting.
