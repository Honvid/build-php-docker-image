FROM step3-compress-nginx-php74:latest

COPY docker-php-ext-linkdoc.ini /usr/local/etc/php/conf.d/docker-php-ext-linkdoc.ini

ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

EXPOSE 9000
STOPSIGNAL SIGTERM

CMD ["php-fpm"]
