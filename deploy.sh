#! /bin/bash

docker stack deploy --with-registry-auth --resolve-image=always -c <(docker-compose config)  phonebook