#!/bin/bash

echo "🚀 Starting CtrlPanel.gg v1.0.1 full setup..."

# Ask user for input (with defaults)
read -p "📍 Enter your panel domain (e.g., panel.example.com) [default: panel.localhost]: " DOMAIN
DOMAIN=${DOMAIN:-panel.localhost}

read -p "📦 Enter MySQL database name [default: ctrlpanel]: " DB_NAME
DB_NAME=${DB_NAME:-ctrlpanel}

read -p "👤 Enter MySQL username [default: ctrluser]: " DB_USER
DB_USER=${DB_USER:-ctrluser}

read -p "🔒 Enter MySQL user password [default: ctrlpass]: " DB_PASS
DB_PASS=${DB_PASS:-ctrlpass}

read -p "📧 Enter email for Let's Encrypt (for SSL) [default: admin@$DOMAIN]: " EMAIL
EMAIL=${EMAIL:-admin@$DOMAIN}

# Update and install required packages
apt update && apt upgrade -y
apt install -y php php-cli php-curl php-mysql php-mbstring php-xml php-bcmath unzip curl git nginx mariadb-server redis composer certbot python3-certbot-nginx ufw

# Open HTTP and HTTPS ports
ufw allow 80
ufw allow 443

# Clone and set up CtrlPanel
git clone https://github.com/ctrlpanel-gg/ctrlpanel.git /var/www/ctrlpanel
cd /var/www/ctrlpanel
composer install --no-interaction --prefer-dist --optimize-autoloader
cp .env.example .env
php artisan key:generate

# Set MySQL database
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Set environment config
sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env

# Run DB setup
php artisan migrate --seed --force
php artisan ctrl:install

# Configure NGINX
cat > /etc/nginx/sites-available/ctrlpanel <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/ctrlpanel/public;

    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/ctrlpanel /etc/nginx/sites-enabled/ctrlpanel
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Get SSL via Let's Encrypt
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL

# Set permissions
chown -R www-data:www-data /var/www/ctrlpanel

echo ""
echo "✅ CtrlPanel.gg v1.0.1 is now fully installed!"
echo "🌐 Access it at: https://${DOMAIN}"
echo "🔐 SSL installed via Let's Encrypt"
echo "📁 Installed at: /var/www/ctrlpanel"
