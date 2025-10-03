1. Create cert for this, put it all on /certs:
OPENSSL
ca.crt
kibana.crt
kibana.key
fleet-server-key.pem
fleet-server-cert.pem
elasticsearch.key
elasticsearch.crt

2. Run:
    docker compose up setup

3. Run:
     Run with
   docker compose \
    -f docker-compose.yml \
    -f extensions/fleet/fleet-compose.yml \
    -f extensions/fleet/agent-apmserver-compose.yml \
     up -d 
4. Create Fleet Enrollment Token