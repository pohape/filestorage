FROM httpd:2.4

RUN sed -i -E \
    -e 's/^#(LoadModule vhost_alias_module .*)/\1/' \
    -e 's/^#(LoadModule autoindex_module .*)/\1/' \
    -e 's/^#(LoadModule rewrite_module .*)/\1/' \
    /usr/local/apache2/conf/httpd.conf

RUN echo "ServerName localhost" >> /usr/local/apache2/conf/httpd.conf
RUN echo "Include conf/extra/storage.conf" >> /usr/local/apache2/conf/httpd.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
