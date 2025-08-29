https://github.com/deviantony/docker-elk/blob/main/setup/.dockerignore

1. tạo tls key cho fleet server
openssl req -x509 -newkey rsa:4096 -keyout fleet-server-key.pem -out fleet-server-cert.pem -days 365 -nodes

2. tạo CA cho AMP server
cp fleet-server-cert.pem ca.crt

