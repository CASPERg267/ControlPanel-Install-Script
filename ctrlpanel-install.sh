#!/bin/bash

echo "Starting CtrlPanel.gg v1.0.1 full setup..."

# Prompt for inputs with defaults
read -p "Enter domain (default: panel.localhost): " DOMAIN
DOMAIN=${DOMAIN:-panel.localhost}

read -p "Enter email for SSL certificate (default: admin@$DOMAIN): " SSL_EMAIL
SSL_EMAIL=${SSL_EMAIL:-admin@$DOMAIN}

read -p "Enter database name (default: ctrlpanel): " DB_NAME
DB_NAME=${DB_NAME:-ctrlpanel}

read -p "Enter database user (default: ctrluser): " DB_USER
DB_USER=${DB_USER:-ctrluser}

read -p "Enter database password (default: ctrlpass): " DB_PASS
DB_PASS=${DB_PASS:-ctrlpass}

read -p "Enter MySQL root password (leave blank if not set): " MYSQL_ROOT_PASS

APP_DIR="/var/www/ctrlpanel"
REPO_URL="https://github.com/Ctrlpanel-gg/panel.git"

# Install required packages
apt update && apt upgrade -y
apt install -y php php-cli php-curl php-mysql php-xml php-bcmath php-mbstring curl git unzip composer nginx ufw mariadb-server redis certbot python3-certbot-nginx

# Configure UFW
ufw allow 'Nginx Full'

# Clone repo
if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO_URL" "$APP_DIR" || { echo "Failed to clone repository."; exit 1; }
fi

cd "$APP_DIR" || exit 1

# Install PHP dependencies
composer install --no-interaction --prefer-dist --optimize-autoloader

# Setup env
cp .env.example .env

sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" .env

# Setup database
if [ -z "$MYSQL_ROOT_PASS" ]; then
  mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
else
  mysql -u root -p"$MYSQL_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
fi

# Setup Laravel app
php artisan key:generate
php artisan migrate --force
php artisan config:cache
php artisan route:cache

# Set permissions
chown -R www-data:www-data "$APP_DIR"
chmod -R 755 "$APP_DIR"

# NGINX config
NGINX_CONF="/etc/nginx/sites-available/ctrlpanel"

cat > "$NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    root $APP_DIR/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# SSL
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$SSL_EMAIL"

echo ""
echo "CtrlPanel.gg v1.0.1 is now fully installed."
echo "Access it at: https://$DOMAIN"
echo "SSL issued to: $SSL_EMAIL"
echo "Installed at: $APP_DIR"
