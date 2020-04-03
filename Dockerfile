FROM php:7.4-apache
LABEL maintainer="ando <lifeandcoding@gmail.com>"

# Apache doc root
ENV APACHE_DOCUMENT_ROOT=/var/www/html/web

# Allow composer to run as root
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		git \
		libjpeg-dev \
		libpng-dev \
		libfreetype6-dev \
		zlib1g-dev \
		libzip-dev \
		gnupg \
		apt-transport-https \
		ca-certificates \
		build-essential

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg; \
	docker-php-ext-install -j $(nproc) gd mysqli opcache zip bcmath exif

# Clean up
RUN apt-get clean && \
	rm -rf /var/lib/apt/lists/*

# Setup Apache
RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Enable Apache modules
RUN a2enmod rewrite

# Use the default production configuration
RUN mv $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
	echo 'opcache.memory_consumption=128'; \
	echo 'opcache.interned_strings_buffer=8'; \
	echo 'opcache.max_accelerated_files=4000'; \
	echo 'opcache.revalidate_freq=2'; \
	echo 'opcache.fast_shutdown=1'; \
	echo 'opcache.enable_cli=1'; \
	} > $PHP_INI_DIR/conf.d/opcache-recommended.ini

RUN { \
	echo 'cgi.fix_pathinfo=0'; \
	echo 'memory_limit=512M'; \
	echo 'post_max_size=10M'; \
	echo 'upload_max_filesize=10M'; \
	echo 'sendmail_path=/usr/sbin/sendmail -S mail:1025'; \
	} > $PHP_INI_DIR/conf.d/core-recommended.ini

# Setup composer
COPY --from=composer /usr/bin/composer /usr/bin/composer

# Copy codebase
ONBUILD COPY . /var/www/html

# Install composer dependencies
ONBUILD RUN composer install \
	--prefer-dist --no-scripts --no-dev --optimize-autoloader
	
# Fix permissions
ONBUILD RUN chmod 777 -R /var/www/html/web/app/uploads
ONBUILD RUN usermod -u 1000 www-data
