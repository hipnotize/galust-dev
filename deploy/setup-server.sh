#!/usr/bin/env bash
# One-time setup on the web server, safe to re-run:
#   1. backs up /etc/nginx;
#   2. creates the site-deploy user, which can only rsync into the web root (rrsync -wo);
#   3. installs an HTTP-only server block, gets a Let's Encrypt certificate through the shared webroot;
#   4. installs the full HTTPS config. Every nginx change goes through `nginx -t` before a reload.
#
# Usage (on the server): sudo DOMAIN=example.dev ./setup-server.sh deploy_key.pub nginx-site.conf
# Rollback: rm /etc/nginx/sites-enabled/$DOMAIN && nginx -t && systemctl reload nginx
set -euo pipefail

: "${DOMAIN:?set DOMAIN=your.domain}"
pubkey_file="${1:?path to the deploy public key}"
template="${2:?path to nginx-site.conf}"
user=site-deploy
root="/var/www/$DOMAIN"
conf="/etc/nginx/sites-available/$DOMAIN"
link="/etc/nginx/sites-enabled/$DOMAIN"
var="$(echo "$DOMAIN" | tr -c 'a-zA-Z0-9\n' '_')"

# A config that fails `nginx -t` is unlinked at once, so a later reload or reboot can't take down the other sites.
reload_nginx() {
  if nginx -t; then systemctl reload nginx
  else rm -f "$link"; echo "nginx -t failed: $DOMAIN unlinked, other sites untouched" >&2; exit 1
  fi
}

backup="/root/nginx-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$backup" -C /etc nginx
echo "nginx config backed up to $backup"

id "$user" >/dev/null 2>&1 || useradd --system --create-home --shell /bin/sh "$user"
install -d -o "$user" -g www-data -m 755 "$root"
install -d -o "$user" -g "$user" -m 700 "/home/$user/.ssh"
printf 'restrict,command="/usr/bin/rrsync -wo %s" %s\n' "$root" "$(cat "$pubkey_file")" > "/home/$user/.ssh/authorized_keys"
chown "$user:$user" "/home/$user/.ssh/authorized_keys"
chmod 600 "/home/$user/.ssh/authorized_keys"
[ -f "$root/index.html" ] || echo '<!doctype html><title>Coming soon</title><p>Coming soon.</p>' > "$root/index.html"

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  cat > "$conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 404; }
}
EOF
  ln -sf "$conf" "$link"
  reload_nginx
  certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --deploy-hook "systemctl reload nginx"
fi

sed -e "s/__SITE__/$var/g" -e "s/__DOMAIN__/$DOMAIN/g" "$template" > "$conf"
ln -sf "$conf" "$link"
reload_nginx
echo "done: https://$DOMAIN serves $root, deploy user $user"
