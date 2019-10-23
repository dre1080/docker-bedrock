FROM owasp/modsecurity-crs:v3.2-modsec3-apache AS modsec

FROM php:apache
LABEL maintainer="ando <lifeandcoding@gmail.com>"

# For fuzzylib
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/

# Apache doc root
ENV APACHE_DOCUMENT_ROOT=/var/www/html/web

# Allow composer to run as root
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		git \
		mercurial \
		subversion \
		libjpeg-dev \
		libpng-dev \
		zlib1g-dev \
		libzip-dev \
		gnupg \
		apt-transport-https \
		ca-certificates \
		build-essential \
		# modsec specific deps:
		libcurl4-gnutls-dev \
		libxml2-dev \
		libgeoip-dev \
		liblmdb-dev \
		lua5.2-dev \
		libyajl-dev \
		apache2-dev

# Install PHP extensions
RUN docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr && \
	docker-php-ext-install gd mysqli opcache zip bcmath exif

# Clean up
RUN apt-get clean && \
	rm -rf /var/lib/apt/lists/*

# Setup ModSecurity CRS
COPY --from=modsec /usr/local/lib /usr/local/lib
COPY --from=modsec /usr/local/modsecurity /usr/local/modsecurity
RUN ldconfig

COPY --from=modsec /usr/local/apache2/modules/mod_security3.so /usr/lib/apache2/modules/mod_security3.so
COPY --from=modsec /opt/owasp-modsecurity-crs-3.2 /opt/owasp-modsecurity-crs-3.2
COPY --from=modsec /etc/modsecurity.d /etc/modsecurity.d

RUN echo 'SecAction "id:900130,phase:1,nolog,pass,t:none, setvar:tx.crs_exclusions_wordpress=1"' > /etc/modsecurity.d/owasp-crs/crs-setup.conf

RUN echo 'LoadModule security3_module "/usr/lib/apache2/modules/mod_security3.so"' > /etc/apache2/mods-available/security.load

RUN { \
	echo '<IfModule security3_module>'; \
	echo "\tmodsecurity_rules_file '/etc/modsecurity.d/include.conf'"; \
	echo '</IfModule>'; \
	} > /etc/apache2/mods-available/security.conf

# Setup Apache
RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Enable Apache modules
RUN a2enmod rewrite security

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
