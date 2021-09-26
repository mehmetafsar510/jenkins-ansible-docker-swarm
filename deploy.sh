#! /bin/bash
cd /home/ec2-user/jenkins-dockerswarm/
docker stack deploy --with-registry-auth --resolve-image=always -c <(docker-compose config)  phonebook