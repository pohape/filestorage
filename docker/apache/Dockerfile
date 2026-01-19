FROM php:8.3-apache

RUN a2enmod vhost_alias auth_basic authn_file rewrite
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY filemanager.php /var/www/html/filemanager.php

ENTRYPOINT ["/entrypoint.sh"]
