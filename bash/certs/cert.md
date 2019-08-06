
#Download that certbot-route53.sh and run the below command.
certbot certonly --non-interactive --manual --manual-auth-hook /root/certs/certbot-route53.sh --manual-cleanup-hook /root/certs/certbot-route53.sh --preferred-challenge dns --config-dir /root/certs/letsencrypt --work-dir /root/certs/letsencrypt --logs-dir /root/certs/letsencrypt --domains saofflinerepo.cliqrtech.com --manual-public-ip-logging-ok
