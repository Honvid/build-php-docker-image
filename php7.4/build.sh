CurrentDir="$( cd "$( dirname "$0"  )" && pwd  )"
cd $CurrentDir

if [ ! -f "tmp/ready" ];then
    rm -rf tmp
    mkdir tmp && cd tmp
    git clone --depth=1 https://github.com/edenhill/librdkafka.git librdkafka
    git clone --depth=1 https://github.com/arnaud-lb/php-rdkafka.git php-rdkafka
    git clone --depth=1 https://github.com/mongodb/mongo-php-driver.git mongo-php-driver
    cd mongo-php-driver && git submodule sync && git submodule update --init && cd ..
    git clone --depth=1 https://github.com/phpredis/phpredis.git phpredis
    git clone --depth=1 https://github.com/runkit7/runkit7.git runkit7
    git clone --depth=1 https://github.com/swoole/swoole-src.git swoole-src
    git clone --depth=1 https://github.com/xdebug/xdebug.git xdebug
    git clone --depth=1 https://github.com/grpc/grpc grpc
    cd grpc && git submodule update --init && cd ..
    touch ready
    cd ..
fi

docker build -t step1-build-nginx-php74-fpm:latest . \
&& docker run -d --name step2-run-nginx-php74-fpm step1-build-nginx-php74-fpm:latest \
&& docker export step2-run-nginx-php74-fpm | docker import - step3-compress-nginx-php74:latest \
&& cd $CurrentDir/compress && docker build -t honvid/php-fpm . \
&& cd $CurrentDir/compress-dev && docker build -t honvid/php-fpm:dev . \
&& docker rm -f step2-run-nginx-php74-fpm && docker rmi step3-compress-nginx-php74:latest
