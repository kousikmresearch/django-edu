#!/bin/bash

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# Install system dependencies
sudo apt-get install -y python3-pip python3-dev default-mysql-server default-mysql-client nginx curl

# Create project directory
PROJECT_DIR="/home/$USER/django-edu"
if [ ! -d "$PROJECT_DIR" ]; then
    mkdir -p $PROJECT_DIR
fi
cd $PROJECT_DIR

# Pull latest code
if [ ! -d ".git" ]; then
    git clone https://github.com/kousikmresearch/django-edu.git .
else
    git fetch origin
    git reset --hard origin/main
fi

# Install Python dependencies
pip3 install -r requirements.txt

# Configure MySQL
sudo mysql -e "CREATE DATABASE eduapp;"
sudo mysql -e "CREATE USER 'eduapp'@'localhost' IDENTIFIED BY 'eduapp';"
sudo mysql -e "GRANT ALL PRIVILEGES ON eduapp.* TO 'eduapp'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Configure Django settings
sed -i 's/DEBUG = True/DEBUG = False/' edu/settings.py
sed -i 's/ALLOWED_HOSTS = []/ALLOWED_HOSTS = [\"*\"]/' edu/settings.py

# Collect static files
python manage.py collectstatic --noinput

# Apply migrations
python manage.py migrate

# Configure Gunicorn
sudo tee /etc/systemd/system/gunicorn.service > /dev/null <<EOL
[Unit]
Description=gunicorn daemon
After=network.target

[Service]
User=$USER
Group=www-data
WorkingDirectory=$PROJECT_DIR
ExecStart=/home/$USER/.local/bin/gunicorn --access-logfile - --workers 3 --bind unix:$PROJECT_DIR/edu.sock edu.wsgi:application

[Install]
WantedBy=multi-user.target
EOL

# Configure Nginx
sudo tee /etc/nginx/sites-available/django-edu > /dev/null <<EOL
server {
    listen 80;
    server_name _;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root $PROJECT_DIR;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$PROJECT_DIR/edu.sock;
    }
}
EOL

# Enable and restart services
sudo ln -sf /etc/nginx/sites-available/django-edu /etc/nginx/sites-enabled
sudo systemctl daemon-reload
sudo systemctl restart nginx
sudo systemctl enable gunicorn
sudo systemctl restart gunicorn
