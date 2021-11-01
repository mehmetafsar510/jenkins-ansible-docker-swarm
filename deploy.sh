#! /bin/bash

amazon-linux-extras install epel -y
yum -y install nginx vim
yum -y install certbot python2-certbot-ngi

sh -c "cat >> /etc/nginx/conf.d/jenkins.conf<< 'EOF'
################################################
# Nginx Proxy configuration
#################################################
upstream jenkins {
  server {JENKINSERVERIP}:8000 fail_timeout=0;
}
server {
  listen 80;
  server_name phonebook.mehmetafsar.net;

  location / {
    proxy_set_header        Host $host:$server_port;
    proxy_set_header        X-Real-IP $remote_addr;
    proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header        X-Forwarded-Proto $scheme;
    proxy_pass              http://jenkins;
    # Required for new HTTP-based CLI
    proxy_http_version 1.1;
    proxy_request_buffering off;
    proxy_buffering off; # Required for HTTP-based CLI to work over SSL
  }
}             
EOF"
sed -i "s/{JENKINSERVERIP}/${JENKINSERVERIP}/g" /etc/nginx/conf.d/jenkins.conf
sed -i "s/{FullDomainName}/${FullDomainName}/g" /etc/nginx/conf.d/jenkins.conf

systemctl enable --now nginx
systemctl restart nginx
export DOMAIN="${FullDomainName}"
export ALERTS_EMAIL="${OperatorEMail}"
certbot --nginx --redirect -d $DOMAIN --preferred-challenges http --agree-tos -n -m $ALERTS_EMAIL --keep-until-expiring
crontab -l > /tmp/mycrontab
echo '0 12 * * * /usr/bin/certbot renew --quiet' >> /tmp/mycrontab
crontab /tmp/mycrontab