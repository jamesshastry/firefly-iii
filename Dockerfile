FROM serversideup/php:8.4-fpm-nginx

USER root

RUN install-php-extensions \
    bcmath \
    intl \
    gd

# Switch to root to configure storage and permissions
USER root

# Copy application files
COPY --chown=www-data:www-data . /var/www/html

# Switch to www-data for composer install
USER www-data

# Install Composer dependencies
# We use --no-dev to keep the image small
# We use --ignore-platform-reqs to avoid issues if the container PHP version is slightly newer (e.g. 8.5-dev) than dependencies allow
# We use --no-scripts to prevent auto-running 'php artisan' commands during build (which fail without DB/Env)
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress --ignore-platform-reqs --no-scripts

# Create the data directory for the SQLite database volume
# Railway will mount a volume here. We need to ensure the application can write to it.
USER root
RUN mkdir -p /var/www/html/storage/database && \
    chown -R www-data:www-data /var/www/html/storage/database

# Configure environment variables for Railway/Production
ENV APP_ENV=production
ENV APP_DEBUG=false
ENV LOG_CHANNEL=stderr
ENV DB_CONNECTION=sqlite
# Point the SQLite database to the persistent volume path
ENV DB_DATABASE=/var/www/html/storage/database/database.sqlite

# Entrypoint script to handle startup tasks
# We simply append a command to the default entrypoint to run migrations
COPY --chmod=755 <<EOF /etc/entrypoint.d/99-firefly-init.sh
#!/bin/sh
# Ensure the database file exists if it's new
if [ ! -f /var/www/html/storage/database/database.sqlite ]; then
    echo "Creating empty SQLite database..."
    touch /var/www/html/storage/database/database.sqlite
    chown www-data:www-data /var/www/html/storage/database/database.sqlite
fi

echo "Running database migrations..."
php artisan migrate --force

echo "Clearing caches..."
php artisan config:clear
php artisan cache:clear
php artisan route:cache
php artisan view:cache
EOF

# Switch back to web user
USER www-data
