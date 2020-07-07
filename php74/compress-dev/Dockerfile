FROM step3-compress-nginx-php74:latest

COPY docker-php-ext-extra.ini /usr/local/etc/php/conf.d/docker-php-ext-extra.ini

EXPOSE 9000
STOPSIGNAL SIGTERM

CMD ["php-fpm"]
