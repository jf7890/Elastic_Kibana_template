#!/bin/bash
docker compose \
-f docker-compose.yml \
-f extensions/fleet/fleet-compose.yml \
-f web/web-compose.yml \
up -d
