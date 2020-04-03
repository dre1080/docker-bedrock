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
RUN set -eux; \
	a2enmod rewrite expires; \
	\
	# https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
	a2enmod remoteip; \
	{ \
		echo 'RemoteIPHeader X-Forwarded-For'; \
		# these IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
		echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
		echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
		echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
		echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
		echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
	} > /etc/apache2/conf-available/remoteip.conf; \
	a2enconf remoteip; \
# https://github.com/docker-library/wordpress/issues/383#issuecomment-507886512
# (replace all instances of "%h" with "%a" in LogFormat)
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

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

RUN { \
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > $PHP_INI_DIR/conf.d/error-logging.ini

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
