#!/bin/sh

# This script wraps docker-php-ext-install, properly configuring the system.
#
# Copyright (c) Michele Locati, 2018
#
# Source: https://github.com/mlocati/docker-php-extension-installer
#
# License: MIT - see https://github.com/mlocati/docker-php-extension-installer/blob/master/LICENSE

# Let's set a sane environment
set -o errexit
set -o nounset

# Reset the Internal Field Separator
resetIFS() {
	IFS='
'
}

# Set these variables:
# - DISTRO containing distribution name (eg 'alpine', 'debian')
# - DISTO_VERSION containing distribution name and its version(eg 'alpine@3.10', 'debian@9')
setDistro() {
	if ! test -r /etc/os-release; then
		printf 'The file /etc/os-release is not readable\n' >&2
		exit 1
	fi
	DISTRO="$(cat /etc/os-release | grep -E ^ID= | cut -d = -f 2)"
	DISTRO_VERSION="$(printf '%s@%s' $DISTRO $(cat /etc/os-release | grep -E ^VERSION_ID= | cut -d = -f 2 | cut -d '"' -f 2 | cut -d . -f 1,2))"
}

# Set the PHP_MAJMIN_VERSION variable containing the PHP Major-Minor version as an integer value, in format MMmm (example: 506 for PHP 5.6.15)
setPHPMajorMinor() {
	PHP_MAJMIN_VERSION=$(php-config --version | awk -F. '{print $1*100+$2}')
}

# Get the normalized list of already installed PHP modules
#
# Output:
#   Space-separated list of module handles
getPHPInstalledModules() {
	getPHPInstalledModules_result=''
	IFS='
'
	for getPHPInstalledModules_module in $(php -m); do
		getPHPInstalledModules_moduleNormalized=''
		case "$getPHPInstalledModules_module" in
			\[PHP\ Modules\]) ;;
			\[Zend\ Modules\])
				break
				;;
			Core | PDO | PDO_* | Phar | Reflection | SimpleXML | SPL | SQLite | Xdebug)
				getPHPInstalledModules_moduleNormalized=$(LC_CTYPE=C printf '%s' "$getPHPInstalledModules_module" | tr '[:upper:]' '[:lower:]')
				;;
			Zend\ OPcache)
				getPHPInstalledModules_moduleNormalized='opcache'
				;;
			*\ * | *A* | *B* | *C* | *D* | *E* | *F* | *G* | *H* | *I* | *J* | *K* | *L* | *M* | *N* | *O* | *P* | *Q* | *R* | *S* | *T* | *U* | *V* | *W* | *X* | *Y* | *Z*)
				printf '### WARNING Unrecognized module name: %s ###\n' "$getPHPInstalledModules_module" >&2
				;;
			*)
				getPHPInstalledModules_moduleNormalized="$getPHPInstalledModules_module"
				;;
		esac
		if test -n "$getPHPInstalledModules_moduleNormalized"; then
			if ! stringInList "$getPHPInstalledModules_moduleNormalized" "$getPHPInstalledModules_result"; then
				getPHPInstalledModules_result="$getPHPInstalledModules_result $getPHPInstalledModules_moduleNormalized"
			fi
		fi
	done
	resetIFS
	printf '%s' "${getPHPInstalledModules_result# }"
}

# Get the handles of the modules to be installed
#
# Arguments:
#   $@: all module handles
#
# Set:
#   PHP_MODULES_TO_INSTALL
#
# Output:
#   Nothing
processCommandArguments() {
	processCommandArguments_alreadyInstalled="$(getPHPInstalledModules)"
	processCommandArguments_endArgs=0
	PHP_MODULES_TO_INSTALL=''
	while :; do
		if test $# -lt 1; then
			break
		fi
		processCommandArguments_skip=0
		if test $processCommandArguments_endArgs -eq 0; then
			case "$1" in
				--cleanup)
					printf '### WARNING the %s option is deprecated (we always cleanup everything) ###\n' "$1" >&2
					processCommandArguments_skip=1
					;;
				--)
					processCommandArguments_skip=1
					processCommandArguments_endArgs=1
					;;
				-*)
					printf 'Unrecognized option: %s\n' "$1" >&2
					exit 1
					;;
			esac
		fi
		if test $processCommandArguments_skip -eq 0; then
			case "$1" in
				pecl_http)
					processCommandArguments_name='http'
					;;
				*)
					processCommandArguments_name=$1
					;;
			esac
			if stringInList "$processCommandArguments_name" "$PHP_MODULES_TO_INSTALL"; then
				printf '### WARNING Duplicated module name specified: %s ###\n' "$processCommandArguments_name" >&2
			elif stringInList "$processCommandArguments_name" "$processCommandArguments_alreadyInstalled"; then
				printf '### WARNING Module already installed: %s ###\n' "$processCommandArguments_name" >&2
			else
				PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL $processCommandArguments_name"
			fi
		fi
		shift
	done
	PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL# }"
}

# Sort the modules to be installed, in order to fix dependencies
#
# Update:
#   PHP_MODULES_TO_INSTALL
#
# Output:
#   Nothing
sortModulesToInstall() {
	if stringInList 'apcu_bc' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'apcu_bc' "$PHP_MODULES_TO_INSTALL")"
		sortModulesToInstall_alreadyInstalled="$(getPHPInstalledModules)"
		if ! stringInList 'apcu' "$PHP_MODULES_TO_INSTALL" && ! stringInList 'apcu' "$sortModulesToInstall_alreadyInstalled"; then
			PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL apcu"
		fi
		PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL apcu_bc"
	fi
	if stringInList 'igbinary' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'igbinary' "$PHP_MODULES_TO_INSTALL")"
		if test -z "$PHP_MODULES_TO_INSTALL"; then
			PHP_MODULES_TO_INSTALL='igbinary'
		else
			PHP_MODULES_TO_INSTALL="igbinary $PHP_MODULES_TO_INSTALL"
		fi
	fi
	if stringInList 'msgpack' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'msgpack' "$PHP_MODULES_TO_INSTALL")"
		if test -z "$PHP_MODULES_TO_INSTALL"; then
			PHP_MODULES_TO_INSTALL='msgpack'
		else
			PHP_MODULES_TO_INSTALL="msgpack $PHP_MODULES_TO_INSTALL"
		fi
	fi
	if stringInList 'http' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'http' "$PHP_MODULES_TO_INSTALL")"
		sortModulesToInstall_alreadyInstalled="$(getPHPInstalledModules)"
		if ! stringInList 'propro' "$PHP_MODULES_TO_INSTALL" && ! stringInList 'propro' "$sortModulesToInstall_alreadyInstalled"; then
			PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL propro"
		fi
		if ! stringInList 'raphf' "$PHP_MODULES_TO_INSTALL" && ! stringInList 'raphf' "$sortModulesToInstall_alreadyInstalled"; then
			PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL raphf"
		fi
		PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL http"
	fi
}

# Get the required APT/APK packages for a specific PHP version and for the list of module handles
#
# Arguments:
#   $1: the numeric PHP Major-Minor version
#   $@: the PHP module handles
#
# Set:
#   PACKAGES_PERSISTENT
#   PACKAGES_VOLATILE
#   PACKAGES_PREVIOUS
buildRequiredPackageLists() {
	buildRequiredPackageLists_persistent=''
	buildRequiredPackageLists_volatile=''
	buildRequiredPackageLists_phpv=$1
	case "$DISTRO" in
		alpine)
			apk update
			;;
	esac
	case "$DISTRO_VERSION" in
		alpine@*)
			buildRequiredPackageLists_volatile="$PHPIZE_DEPS"
			if test -z "$(apk info 2>/dev/null | grep -E ^libssl)"; then
				buildRequiredPackageLists_libssl='libssl1.0'
			elif test -z "$(apk info 2>/dev/null | grep -E '^libressl.*-libtls')"; then
				buildRequiredPackageLists_libssl=$(apk search -q libressl*-libtls)
			else
				buildRequiredPackageLists_libssl=''
			fi
			;;
		debian@9)
			buildRequiredPackageLists_libssldev='libssl1.0-dev'
			;;
		debian@*)
			buildRequiredPackageLists_libssldev='libssl([0-9]+(\.[0-9]+)*)?-dev$'
			;;
	esac
	while :; do
		if test $# -lt 2; then
			break
		fi
		shift
		case "$1@$DISTRO" in
			amqp@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent rabbitmq-c"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile rabbitmq-c-dev"
				;;
			amqp@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librabbitmq[0-9]"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librabbitmq-dev libssh-dev"
				;;
			bz2@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libbz2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile bzip2-dev"
				;;
			bz2@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libbz2-dev"
				;;
			cmark@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake"
				;;
			cmark@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake"
				;;
			decimal@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmpdec2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmpdec-dev"
				;;
			enchant@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent enchant"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile enchant-dev"
				;;
			enchant@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libenchant1c2a"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libenchant-dev"
				;;
			ffi@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libffi"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libffi-dev"
				;;
			ffi@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libffi-dev"
				;;
			gd@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetype libjpeg-turbo libpng libxpm"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetype-dev libjpeg-turbo-dev libpng-dev libxpm-dev"
				if test $buildRequiredPackageLists_phpv -le 506; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libvpx"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libvpx-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libwebp"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libwebp-dev"
				fi
				;;
			gd@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libfreetype6 libjpeg62-turbo libpng[0-9]+-[0-9]+$ libxpm4"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libfreetype6-dev libjpeg62-turbo-dev libpng-dev libxpm-dev"
				if test $buildRequiredPackageLists_phpv -le 506; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libvpx[0-9]+$"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libvpx-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libwebp[0-9]+$"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libwebp-dev"
				fi
				;;
			gettext@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libintl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile gettext-dev"
				;;
			gmagick@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent graphicsmagick"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile graphicsmagick-dev libtool"
				;;
			gmagick@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libgraphicsmagick(-q16-)?[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgraphicsmagick1-dev"
				;;
			gmp@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent gmp"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile gmp-dev"
				;;
			gmp@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgmp-dev"
				;;
			grpc@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev linux-headers"
				;;
			grpc@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev"
				;;
			http@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libevent"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev curl-dev libevent-dev"
				if test $buildRequiredPackageLists_phpv -le 506; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libidn"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libidn-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent icu-libs libidn"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev libidn-dev"
				fi
				;;
			http@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libcurl3-gnutls libevent[0-9\.\-]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev libgnutls28-dev libcurl4-gnutls-dev libevent-dev"
				if test $buildRequiredPackageLists_phpv -le 506; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libidn1[0-9+]-dev$"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libicu[0-9]+$ libidn2-[0-9+]$"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libicu-dev libidn2-[0-9+]-dev$"
				fi
				;;
			imagick@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent imagemagick"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile imagemagick-dev"
				;;
			imagick@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmagickwand-6.q16-[0-9]+$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmagickwand-dev"
				;;
			imap@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent c-client $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile krb5-dev imap-dev libressl-dev"
				;;
			imap@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libc-client2007e"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libkrb5-dev"
				case "$DISTRO_VERSION" in
					debian@9)
						buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile $buildRequiredPackageLists_libssldev comerr-dev krb5-multidev libc-client2007e libgssrpc4 libkadm5clnt-mit11 libkadm5srv-mit11 libkdb5-8 libpam0g-dev libssl-doc mlock"
						;;
					*)
						buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libc-client-dev"
						;;
				esac
				;;
			interbase@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev ncurses-dev"
				;;
			interbase@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libfbclient2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile firebird-dev libib-util"
				;;
			intl@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent icu-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev"
				;;
			intl@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libicu[0-9]+$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libicu-dev"
				;;
			ldap@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libldap"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile openldap-dev"
				;;
			ldap@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libldap2-dev"
				;;
			mcrypt@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmcrypt"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmcrypt-dev"
				;;
			mcrypt@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmcrypt4"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmcrypt-dev"
				;;
			memcache@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev"
				;;
			memcache@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev"
				;;
			memcached@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmemcached-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmemcached-dev zlib-dev"
				;;
			memcached@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmemcachedutil2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmemcached-dev zlib1g-dev"
				;;
			mongo@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsasl $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libressl-dev cyrus-sasl-dev"
				;;
			mongo@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile $buildRequiredPackageLists_libssldev libsasl2-dev"
				;;
			mongodb@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent icu-libs libsasl $buildRequiredPackageLists_libssl snappy"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev cyrus-sasl-dev snappy-dev libressl-dev zlib-dev"
				;;
			mongodb@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsnappy[0-9]+(v[0-9]+)?$ libicu[0-9]+$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libicu-dev libsasl2-dev libsnappy-dev $buildRequiredPackageLists_libssldev zlib1g-dev"
				;;
			mssql@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetds"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			mssql@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsybdb5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			oauth@alpine)
				if test $buildRequiredPackageLists_phpv -ge 700; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile pcre-dev"
				fi
				;;
			oauth@debian)
				if test $buildRequiredPackageLists_phpv -ge 700; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpcre3-dev"
				fi
				;;
			odbc@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			odbc@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libodbc1"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			pdo_dblib@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetds"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			pdo_dblib@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsybdb5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			pdo_firebird@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev ncurses-dev"
				;;
			pdo_firebird@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libfbclient2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile firebird-dev libib-util"
				;;
			pdo_odbc@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			pdo_odbc@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libodbc1"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			pdo_pgsql@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent postgresql-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile postgresql-dev"
				;;
			pdo_pgsql@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libpq5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpq-dev"
				;;
			pdo_sqlsrv@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++ unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			pdo_sqlsrv@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libodbc1 odbcinst"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			pgsql@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent postgresql-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile postgresql-dev"
				;;
			pgsql@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libpq5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpq-dev"
				;;
			pspell@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent aspell-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile aspell-dev"
				;;
			pspell@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libaspell15"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpspell-dev"
				;;
			rdkafka@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librdkafka"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librdkafka-dev"
				;;
			rdkafka@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librdkafka\+*[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librdkafka-dev"
				;;
			recode@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent recode"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile recode-dev"
				;;
			recode@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librecode0"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librecode-dev"
				;;
			redis@alpine)
				if test $buildRequiredPackageLists_phpv -ge 700; then
					case "$DISTRO_VERSION" in
						alpine@3.7)
							buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent zstd"
							;;
						*)
							buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent zstd-libs"
							;;
					esac
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zstd-dev"
				fi
				;;
			redis@debian)
				if test $buildRequiredPackageLists_phpv -ge 700; then
					case "$DISTRO_VERSION" in
						debian@8)
							## There's no APT package for libzstd
							;;
						debian@9)
							## libzstd is too old (available: 1.1.2, required: 1.3.0+)
							;;
						*)
							buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzstd[0-9]*$"
							buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libzstd-dev"
							;;
					esac
				fi
				;;
			snuffleupagus@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent pcre"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile pcre-dev"
				;;
			snuffleupagus@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpcre3-dev"
				;;
			snmp@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent net-snmp-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile net-snmp-dev"
				;;
			snmp@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent snmp"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libsnmp-dev"
				;;
			soap@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			soap@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			solr@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile curl-dev libxml2-dev"
				;;
			solr@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libcurl3-gnutls"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libcurl4-gnutls-dev libxml2-dev"
				;;
			sqlsrv@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++ unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			sqlsrv@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			ssh2@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libssh2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libssh2-dev"
				;;
			ssh2@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libssh2-1-dev"
				;;
			sybase_ct@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetds"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			sybase_ct@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libct4"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			tdlib@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++ $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile git cmake gperf zlib-dev libressl-dev linux-headers readline-dev"
				;;
			tdlib@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile git cmake gperf zlib1g-dev $buildRequiredPackageLists_libssldev"
				;;
			tidy@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent tidyhtml-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile tidyhtml-dev"
				;;
			tidy@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libtidy5*"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libtidy-dev"
				;;
			uuid@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libuuid"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile util-linux-dev"
				;;
			uuid@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile uuid-dev"
				;;
			wddx@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			wddx@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			xmlrpc@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			xmlrpc@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			xsl@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libxslt"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxslt-dev libgcrypt-dev"
				;;
			xsl@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libxslt1.1"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxslt-dev"
				;;
			yaml@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent yaml"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile yaml-dev"
				;;
			yaml@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libyaml-0-2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libyaml-dev"
				;;
			zip@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzip"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake gnutls-dev libzip-dev libressl-dev zlib-dev"
				;;
			zip@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzip[0-9]$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake gnutls-dev $buildRequiredPackageLists_libssldev libzip-dev libbz2-dev zlib1g-dev"
				case "$DISTRO_VERSION" in
					debian@8)
						# Debian Jessie doesn't seem to provide libmbedtls
						;;
					*)
						buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmbedtls[0-9]*$"
						buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmbedtls-dev"
						;;
				esac
				;;
		esac
	done
	PACKAGES_PERSISTENT=''
	PACKAGES_VOLATILE=''
	PACKAGES_PREVIOUS=''
	if test -z "$buildRequiredPackageLists_persistent$buildRequiredPackageLists_volatile"; then
		return
	fi
	case "$DISTRO" in
		debian)
			DEBIAN_FRONTEND=noninteractive apt-get update -q
			;;
	esac
	if test -n "$buildRequiredPackageLists_persistent"; then
		PACKAGES_PERSISTENT="$(expandPackagesToBeInstalled $buildRequiredPackageLists_persistent)"
		if test -s "$IPE_ERRFLAG_FILE"; then
			exit 1
		fi
	fi
	if test -n "$buildRequiredPackageLists_volatile"; then
		buildRequiredPackageLists_packages="$(expandPackagesToBeInstalled $buildRequiredPackageLists_volatile)"
		if test -s "$IPE_ERRFLAG_FILE"; then
			exit 1
		fi
		resetIFS
		for buildRequiredPackageLists_package in $buildRequiredPackageLists_packages; do
			if ! stringInList "$buildRequiredPackageLists_package" "$PACKAGES_PERSISTENT"; then
				PACKAGES_VOLATILE="$PACKAGES_VOLATILE $buildRequiredPackageLists_package"
			fi
		done
		PACKAGES_VOLATILE="${PACKAGES_VOLATILE# }"
	fi
	if test -n "$PACKAGES_PERSISTENT$PACKAGES_VOLATILE"; then
		case "$DISTRO" in
			debian)
				PACKAGES_PREVIOUS="$(dpkg --get-selections | grep -E '\sinstall$' | awk '{ print $1 }')"
				;;
		esac
	fi
}

# Get the full list of APT/APK packages that will be installed, given the required packages
#
# Arguments:
#   $1: the list of required APT/APK packages
#
# Output:
#   Space-separated list of every APT/APK packages that will be installed
expandPackagesToBeInstalled() {
	expandPackagesToBeInstalled_result=''
	case "$DISTRO" in
		alpine)
			expandPackagesToBeInstalled_log="$(apk add --simulate $@ 2>&1 || printf '\nERROR: apk failed\n')"
			if test -n "$(printf '%s' "$expandPackagesToBeInstalled_log" | grep -E '^ERROR:')"; then
				printf 'FAILED TO LIST THE WHOLE PACKAGE LIST FOR\n' >&2
				printf '%s ' "$@" >&2
				printf '\n\nCOMMAND OUTPUT:\n%s\n' "$expandPackagesToBeInstalled_log" >&2
				echo 'y' >"$IPE_ERRFLAG_FILE"
				exit 1
			fi
			IFS='
'
			for expandPackagesToBeInstalled_line in $expandPackagesToBeInstalled_log; do
				if test -n "$(printf '%s' "$expandPackagesToBeInstalled_line" | grep -E '^\([0-9]*/[0-9]*) Installing ')"; then
					expandPackagesToBeInstalled_result="$expandPackagesToBeInstalled_result $(printf '%s' "$expandPackagesToBeInstalled_line" | cut -d ' ' -f 3)"
				fi
			done
			resetIFS
			;;
		debian)
			expandPackagesToBeInstalled_log="$(DEBIAN_FRONTEND=noninteractive apt-get install -sy $@ 2>&1 || printf '\nE: apt-get failed\n')"
			if test -n "$(printf '%s' "$expandPackagesToBeInstalled_log" | grep -E '^E:')"; then
				printf 'FAILED TO LIST THE WHOLE PACKAGE LIST FOR\n' >&2
				printf '%s ' "$@" >&2
				printf '\n\nCOMMAND OUTPUT:\n%s\n' "$expandPackagesToBeInstalled_log" >&2
				echo 'y' >"$IPE_ERRFLAG_FILE"
				exit 1
			fi
			expandPackagesToBeInstalled_inNewPackages=0
			IFS='
'
			for expandPackagesToBeInstalled_line in $expandPackagesToBeInstalled_log; do
				if test $expandPackagesToBeInstalled_inNewPackages -eq 0; then
					if test "$expandPackagesToBeInstalled_line" = 'The following NEW packages will be installed:'; then
						expandPackagesToBeInstalled_inNewPackages=1
					fi
				elif test "$expandPackagesToBeInstalled_line" = "${expandPackagesToBeInstalled_line# }"; then
					break
				else
					resetIFS
					for expandPackagesToBeInstalled_newPackage in $expandPackagesToBeInstalled_line; do
						expandPackagesToBeInstalled_result="$expandPackagesToBeInstalled_result $expandPackagesToBeInstalled_newPackage"
					done
					IFS='
'
				fi
			done
			resetIFS
			;;
	esac
	printf '%s' "${expandPackagesToBeInstalled_result# }"
}

# Install the required APT/APK packages
#
# Arguments:
#   $@: the list of APT/APK packages to be installed
installRequiredPackages() {
	printf '### INSTALLING REQUIRED PACKAGES ###\n'
	printf '# Packages to be kept after installation: %s\n' "$PACKAGES_PERSISTENT"
	printf '# Packages to be used only for installation: %s\n' "$PACKAGES_VOLATILE"

	case "$DISTRO" in
		alpine)
			apk add $PACKAGES_PERSISTENT $PACKAGES_VOLATILE
			;;
		debian)
			DEBIAN_FRONTEND=noninteractive apt-get install -qq -y $PACKAGES_PERSISTENT $PACKAGES_VOLATILE
			;;
	esac
}

# Get the version of an installed APT/APK package
#
# Arguments:
#   $1: the name of the installed package
#
# Output:
#   The numeric part of the package version, with from 1 to 3 numbers
#
# Example:
#   1
#   1.2
#   1.2.3
getInstalledPackageVersion() {
	case "$DISTRO" in
		alpine)
			apk info "$1" | head -n1 | cut -c $((${#1} + 2))- | grep -o -E '^[0-9]+(\.[0-9]+){0,2}'
			;;
		debian)
			dpkg-query --showformat='${Version}' --show "$1" 2>/dev/null | grep -o -E '^[0-9]+(\.[0-9]+){0,2}'
			;;
	esac
}

# Compare two versions
#
# Arguments:
#   $1: the first version
#   $2: the second version
#
# Output
#  -1 if $1 is less than $2
#  0 if $1 is the same as $2
#  1 if $1 is greater than $2
compareVersions() {
	compareVersions_v1="$1.0.0"
	compareVersions_v2="$2.0.0"
	compareVersions_vMin="$(printf '%s\n%s' "$compareVersions_v1" "$compareVersions_v2" | sort -t '.' -n -k1,1 -k2,2 -k3,3 | head -n 1)"
	if test "$compareVersions_vMin" != "$compareVersions_v1"; then
		echo '1'
	elif test "$compareVersions_vMin" = "$compareVersions_v2"; then
		echo '0'
	else
		echo '-1'
	fi
}

# Install a bundled PHP module given its handle
#
# Arguments:
#   $1: the numeric PHP Major-Minor version
#   $2: the handle of the PHP module
#
# Set:
#   UNNEEDED_PACKAGE_LINKS
#
# Output:
#   Nothing
installBundledModule() {
	printf '### INSTALLING BUNDLED MODULE %s ###\n' "$2"
	case "$2" in
		gd)
			if test $1 -le 506; then
				docker-php-ext-configure gd --with-gd --with-jpeg-dir --with-png-dir --with-zlib-dir --with-xpm-dir --with-freetype-dir --enable-gd-native-ttf --with-vpx-dir
			elif test $1 -le 701; then
				docker-php-ext-configure gd --with-gd --with-jpeg-dir --with-png-dir --with-zlib-dir --with-xpm-dir --with-freetype-dir --enable-gd-native-ttf --with-webp-dir
			elif test $1 -le 703; then
				docker-php-ext-configure gd --with-gd --with-jpeg-dir --with-png-dir --with-zlib-dir --with-xpm-dir --with-freetype-dir --with-webp-dir
			else
				docker-php-ext-configure gd --enable-gd --with-webp --with-jpeg --with-xpm --with-freetype
			fi
			;;
		gmp)
			if test $1 -le 506; then
				if ! test -f /usr/include/gmp.h; then
					ln -s /usr/include/x86_64-linux-gnu/gmp.h /usr/include/gmp.h
					UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/include/gmp.h"
				fi
			fi
			;;
		imap)
			case "$DISTRO_VERSION" in
				debian@9)
					installBundledModule_tmp="$(pwd)"
					cd /tmp
					apt-get download libc-client2007e-dev
					dpkg -i --ignore-depends=libssl-dev libc-client2007e-dev*
					rm libc-client2007e-dev*
					cd "$installBundledModule_tmp"
					;;
			esac
			PHP_OPENSSL=yes docker-php-ext-configure imap --with-kerberos --with-imap-ssl
			;;
		interbase | pdo_firebird)
			case "$DISTRO" in
				alpine)
					if ! test -d /tmp/src/firebird; then
						mv "$(getPackageSource https://github.com/FirebirdSQL/firebird/releases/download/R2_5_9/Firebird-2.5.9.27139-0.tar.bz2)" /tmp/src/firebird
						cd /tmp/src/firebird
						#Patch rwlock.h (this has been fixed in later release of firebird 3.x)
						sed -i '194s/.*/#if 0/' src/common/classes/rwlock.h
						./configure --with-system-icu
						# -j option can't be used: make targets must be compiled sequentially
						make -s btyacc_binary gpre_boot libfbstatic libfbclient
						cp gen/firebird/lib/libfbclient.so /usr/lib/
						ln -s /usr/lib/libfbclient.so /usr/lib/libfbclient.so.2
						cd - >/dev/null
					fi
					CFLAGS='-I/tmp/src/firebird/src/jrd -I/tmp/src/firebird/src/include -I/tmp/src/firebird/src/include/gen' docker-php-ext-configure $2
					;;
			esac
			;;
		ldap)
			case "$DISTRO" in
				debian)
					docker-php-ext-configure ldap --with-libdir=lib/$(gcc -dumpmachine)
					;;
			esac
			;;
		mssql | pdo_dblib)
			if test $1 -le 704; then
				if ! test -f /usr/lib/libsybdb.so; then
					ln -s /usr/lib/x86_64-linux-gnu/libsybdb.so /usr/lib/libsybdb.so
					UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/lib/libsybdb.so"
				fi
			fi
			;;
		odbc)
			if test $1 -le 704; then
				docker-php-source extract
				cd /usr/src/php/ext/odbc
				phpize
				sed -ri 's@^ *test +"\$PHP_.*" *= *"no" *&& *PHP_.*=yes *$@#&@g' configure
				./configure --with-unixODBC=shared,/usr
				cd - >/dev/null
			fi
			;;
		pdo_odbc)
			docker-php-ext-configure pdo_odbc --with-pdo-odbc=unixODBC,/usr
			;;
		snmp)
			case "$DISTRO" in
				alpine)
					mkdir -p -m 0755 /var/lib/net-snmp/mib_indexes
					;;
			esac
			;;
		sybase_ct)
			docker-php-ext-configure sybase_ct --with-sybase-ct=/usr
			;;
		tidy)
			case "$DISTRO" in
				alpine)
					if ! test -f /usr/include/buffio.h; then
						ln -s /usr/include/tidybuffio.h /usr/include/buffio.h
						UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/include/buffio.h"
					fi
					;;
			esac
			;;
		zip)
			if test $1 -le 505; then
				docker-php-ext-configure zip
			elif test $1 -le 703; then
				docker-php-ext-configure zip --with-libzip
			else
				docker-php-ext-configure zip --with-zip
			fi
			;;
	esac
	docker-php-ext-install -j$(nproc) "$2"
	case "$2" in
		imap)
			case "$DISTRO_VERSION" in
				debian@9)
					dpkg -r libc-client2007e-dev
					;;
			esac
			;;
	esac
}

# Fetch a tar.gz file, extract it and returns the path of the extracted folder.
#
# Arguments:
#   $1: the URL of the file to be downloaded
#
# Output:
#   The path of the extracted directory
getPackageSource() {
	mkdir -p /tmp/src
	getPackageSource_tempFile=$(mktemp -p /tmp/src)
	curl -L -s -S -o "$getPackageSource_tempFile" "$1"
	getPackageSource_tempDir=$(mktemp -p /tmp/src -d)
	cd "$getPackageSource_tempDir"
	tar -xzf "$getPackageSource_tempFile" 2>/dev/null || tar -xf "$getPackageSource_tempFile"
	cd - >/dev/null
	unlink "$getPackageSource_tempFile"
	getPackageSource_outDir=''
	for getPackageSource_i in $(ls "$getPackageSource_tempDir"); do
		if test -n "$getPackageSource_outDir" || test -f "$getPackageSource_tempDir/$getPackageSource_i"; then
			getPackageSource_outDir=''
			break
		fi
		getPackageSource_outDir="$getPackageSource_tempDir/$getPackageSource_i"
	done
	if test -n "$getPackageSource_outDir"; then
		printf '%s' "$getPackageSource_outDir"
	else
		printf '%s' "$getPackageSource_tempDir"
	fi
}

# Install a PHP module given its handle from source code
#
# Arguments:
#   $1: the handle of the PHP module
#   $2: the URL of the module source code
#   $3: the options of the configure command
#   $4: the value of CFLAGS
installModuleFromSource() {
	printf '### INSTALLING MODULE %s FROM SOURCE CODE ###\n' "$1"
	installModuleFromSource_dir="$(getPackageSource "$2")"
	case "$1" in
		snuffleupagus)
			cd "$installModuleFromSource_dir/src"
			;;
		*)
			cd "$installModuleFromSource_dir"
			;;
	esac
	phpize
	./configure $3 CFLAGS="${4:-}"
	make -j$(nproc) install
	cd - >/dev/null
	docker-php-ext-enable "$1"
	case "$1" in
		snuffleupagus)
			cp -a "$installModuleFromSource_dir/config/default.rules" "$PHP_INI_DIR/conf.d/snuffleupagus.rules"
			printf 'sp.configuration_file=%s\n' "$PHP_INI_DIR/conf.d/snuffleupagus.rules" >>"$PHP_INI_DIR/conf.d/docker-php-ext-snuffleupagus.ini"
			;;
	esac
}

# Install a PECL PHP module given its handle
#
# Arguments:
#   $1: the numeric PHP Major-Minor version
#   $2: the handle of the PHP module
installPECLModule() {
	printf '### INSTALLING PECL MODULE %s ###\n' "$2"
	installPECLModule_actual="$2"
	installPECLModule_stdin='\n'
	installPECLModule_manuallyInstalled=0
	case "$2" in
		amqp)
			case "$DISTRO_VERSION" in
				debian@8)
					# in Debian Jessie we have librammitmq version 0.5.2
					installPECLModule_actual="$2-1.9.3"
					;;
			esac
			;;
		apcu)
			if test $1 -le 506; then
				installPECLModule_actual="$2-4.0.11"
			fi
			;;
		decimal)
			case "$DISTRO" in
				alpine)
					installPECLModule_src="$(getPackageSource https://codeload.github.com/bematech/libmpdec/tar.gz/master)"
					cd -- "$installPECLModule_src"
					./configure CFLAGS='-w'
					make -j$(nproc)
					make install
					cd - >/dev/null
					;;
			esac
			;;
		gmagick)
			if test $1 -le 506; then
				installPECLModule_actual="$2-1.1.7RC3"
			else
				installPECLModule_actual="$2-beta"
			fi
			;;
		http)
			if test $1 -le 506; then
				installPECLModule_actual="pecl_http-2.6.0"
			else
				installPECLModule_actual="pecl_http"
				if ! test -e /usr/local/lib/libidnkit.so; then
					installPECLModule_src="$(getPackageSource https://jprs.co.jp/idn/idnkit-2.3.tar.bz2)"
					cd -- "$installPECLModule_src"
					./configure
					make -j$(nproc) install
					cd - >/dev/null
				fi
			fi
			;;
		igbinary)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-2.0.8"
			fi
			;;
		memcache)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-2.2.7"
			fi
			;;
		mailparse)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-2.1.6"
			fi
			;;
		memcached)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-2.2.0"
				# --with-libmemcached-dir (default: no)      Set the path to libmemcached install prefix
			else
				installPECLModule_stdin=''
				# --with-libmemcached-dir (default: no)      Set the path to libmemcached install prefix
				installPECLModule_stdin="${installPECLModule_stdin}\n"
				# --with-zlib-dir (default: no)              Set the path to ZLIB install prefix
				installPECLModule_stdin="${installPECLModule_stdin}\n"
				# --with-system-fastlz (default: no)         Use system FastLZ library
				installPECLModule_stdin="${installPECLModule_stdin}no\n"
				# --enable-memcached-igbinary (default: no)  Enable memcached igbinary serializer support
				php --ri igbinary >/dev/null 2>/dev/null && installPECLModule_stdin="${installPECLModule_stdin}yes\n" || installPECLModule_stdin="${installPECLModule_stdin}no\n"
				# --enable-memcached-msgpack (default: no)   Enable memcached msgpack serializer support
				php --ri msgpack >/dev/null 2>/dev/null && installPECLModule_stdin="${installPECLModule_stdin}yes\n" || installPECLModule_stdin="${installPECLModule_stdin}no\n"
				# --enable-memcached-json (default: no)      Enable memcached json serializer support
				installPECLModule_stdin="${installPECLModule_stdin}yes\n"
				# --enable-memcached-protocol (default: no)  Enable memcached protocol support
				installPECLModule_stdin="${installPECLModule_stdin}no\n" # https://github.com/php-memcached-dev/php-memcached/issues/418#issuecomment-449587972
				# --enable-memcached-sasl (default: yes)     Enable memcached sasl support
				installPECLModule_stdin="${installPECLModule_stdin}yes\n"
				# --enable-memcached-session (default: yes)  Enable memcached session handler support
				installPECLModule_stdin="${installPECLModule_stdin}yes\n"
			fi
			;;
		mongo)
			installPECLModule_stdin=''
			# --with-mongo-sasl (default: no)      Build with Cyrus SASL (MongoDB Enterprise Authentication) support?
			installPECLModule_stdin="${installPECLModule_stdin}yes\n"
			;;
		mongodb)
			if test $1 -le 505; then
				installPECLModule_actual="$2-1.5.5"
			fi
			;;
		msgpack)
			if test $1 -le 506; then
				installPECLModule_actual="$2-0.5.7"
			fi
			;;
		oauth)
			if test $1 -le 506; then
				installPECLModule_actual="$2-1.2.3"
			fi
			;;
		opencensus)
			if test $1 -le 702; then
				installPECLModule_actual="$2-alpha"
			else
				installPECLModule_manuallyInstalled=1
				installPECLModule_src="$(getPackageSource https://pecl.php.net/get/opencensus)"
				cd "$installPECLModule_src"/opencensus-*
				find . -name '*.c' -type f -exec sed -i 's/\bZVAL_DESTRUCTOR\b/zval_dtor/g' {} +
				phpize
				./configure
				make install
				cd - >/dev/null
			fi
			;;
		parallel)
			if test $1 -le 701; then
				installPECLModule_actual="$2-0.8.3"
			fi
			;;
		pcov)
			if test $1 -lt 701; then
				installPECLModule_actual="$2-0.9.0"
			fi
			;;
		pdo_sqlsrv | sqlsrv)
			# https://docs.microsoft.com/it-it/sql/connect/php/system-requirements-for-the-php-sql-driver?view=sql-server-2017
			if test $1 -le 700; then
				installPECLModule_actual="$2-5.3.0"
			elif test $1 -le 701; then
				installPECLModule_actual="$2-5.6.1"
			fi
			;;
		propro)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-1.0.2"
			fi
			;;
		pthreads)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-2.0.10"
			fi
			;;
		raphf)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-1.1.2"
			fi
			;;
		rdkafka)
			if test $1 -le 505; then
				installPECLModule_actual="$2-3.0.5"
			else
				installPECLModule_tmp=
				case "$DISTRO" in
					alpine)
						installPECLModule_tmp='librdkafka'
						;;
					debian)
						installPECLModule_tmp='librdkafka*'
						;;
				esac
				if test -n "$installPECLModule_tmp"; then
					installPECLModule_tmp="$(getInstalledPackageVersion "$installPECLModule_tmp")"
					if test -n "$installPECLModule_tmp"; then
						if test $(compareVersions "$installPECLModule_tmp" '0.11.0') -lt 0; then
							installPECLModule_actual="$2-3.1.3"
						fi
					fi
				fi
			fi
			;;
		redis)
			# enable igbinary serializer support?
			php --ri igbinary >/dev/null 2>/dev/null && installPECLModule_stdin='yes\n' || installPECLModule_stdin='no\n'
			# enable lzf compression support?
			installPECLModule_stdin="${installPECLModule_stdin}yes\n"
			if test $1 -le 506; then
				installPECLModule_actual="$2-4.3.0"
			else
				installPECLModule_machine=$(gcc -dumpmachine)
				if ! test -e /usr/include/zstd.h || ! test -e /usr/lib/libzstd.so -o -e "/usr/lib/$installPECLModule_machine/libzstd.so"; then
					installPECLModule_zstdVersion=1.4.4
					installPECLModule_zstdVersionMajor=$(echo $installPECLModule_zstdVersion | cut -d. -f1)
					rm -rf /tmp/src/zstd
					mv "$(getPackageSource https://github.com/facebook/zstd/releases/download/v1.4.4/zstd-$installPECLModule_zstdVersion.tar.gz)" /tmp/src/zstd
					cd /tmp/src/zstd
					make V=0 -j$(nproc) lib
					cp -f lib/libzstd.so "/usr/lib/$installPECLModule_machine/libzstd.so.$installPECLModule_zstdVersion"
					ln -sf "/usr/lib/$installPECLModule_machine/libzstd.so.$installPECLModule_zstdVersion" "/usr/lib/$installPECLModule_machine/libzstd.so.$installPECLModule_zstdVersionMajor"
					ln -sf "/usr/lib/$installPECLModule_machine/libzstd.so.$installPECLModule_zstdVersion" "/usr/lib/$installPECLModule_machine/libzstd.so"
					ln -sf /tmp/src/zstd/lib/zstd.h /usr/include/zstd.h
					UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/include/zstd.h"
					cd - >/dev/null
				fi
				# enable zstd compression support?
				installPECLModule_stdin="${installPECLModule_stdin}yes\n"
			fi
			;;
		solr)
			if test $1 -le 506; then
				installPECLModule_actual="$2-2.4.0"
			fi
			;;
		ssh2)
			if test $1 -le 506; then
				installPECLModule_actual="$2-0.13"
			else
				# see https://bugs.php.net/bug.php?id=78560
				installPECLModule_actual='https://pecl.php.net/get/ssh2'
			fi
			;;
		tdlib)
			if ! test -f /usr/lib/libphpcpp.so || ! test -f /usr/include/phpcpp.h; then
				if test $PHP_MAJMIN_VERSION -le 701; then
					cd "$(getPackageSource https://codeload.github.com/CopernicaMarketingSoftware/PHP-CPP/tar.gz/v2.1.4)"
				elif test $PHP_MAJMIN_VERSION -le 703; then
					cd "$(getPackageSource https://codeload.github.com/CopernicaMarketingSoftware/PHP-CPP/tar.gz/v2.2.0)"
				else
					cd "$(getPackageSource https://codeload.github.com/CopernicaMarketingSoftware/PHP-CPP/tar.gz/444d1f90cf6b7f3cb5178fa0d0b5ab441b0389d0)"
				fi
				make -j$(nproc)
				make install
				cd - >/dev/null
			fi
			installPECLModule_tmp="$(mktemp -p /tmp/src -d)"
			git clone --depth=1 --recurse-submodules https://github.com/yaroslavche/phptdlib.git "$installPECLModule_tmp"
			mkdir "$installPECLModule_tmp/build"
			cd "$installPECLModule_tmp/build"
			cmake -D USE_SHARED_PHPCPP:BOOL=ON ..
			make
			make install
			rm "$PHP_INI_DIR/conf.d/tdlib.ini"
			installPECLModule_manuallyInstalled=1
			;;
		uuid)
			if test $1 -le 506; then
				installPECLModule_actual="$2-1.0.5"
			fi
			;;
		xdebug)
			if test $1 -le 500; then
				installPECLModule_actual="$2-2.0.5"
			elif test $1 -le 503; then
				installPECLModule_actual="$2-2.2.7"
			elif test $1 -le 504; then
				installPECLModule_actual="$2-2.4.1"
			elif test $1 -le 506; then
				installPECLModule_actual="$2-2.5.5"
			elif test $1 -le 700; then
				installPECLModule_actual="$2-2.6.1"
			fi
			;;
		uopz)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-2.0.7"
			elif test $1 -lt 701; then
				installPECLModule_actual="$2-5.0.2"
			fi
			;;
		xhprof)
			if test $1 -le 506; then
				installPECLModule_actual="$2-0.9.4"
			fi
			;;
		yaml)
			if test $1 -lt 700; then
				installPECLModule_actual="$2-1.3.1"
			elif test $1 -lt 701; then
				installPECLModule_actual="$2-2.0.4"
			fi
			;;
	esac
	if test $installPECLModule_manuallyInstalled -eq 0; then
		if test "$2" != "$installPECLModule_actual"; then
			printf '  (installing version %s)\n' "$installPECLModule_actual"
		fi
		printf "$installPECLModule_stdin" | pecl install "$installPECLModule_actual"
	fi
	case "$2" in
		apcu_bc)
			# apcu_bc must be loaded after apcu
			docker-php-ext-enable --ini-name "xx-php-ext-$2.ini" apc
			;;
		http)
			# http must be loaded after raphf and propro
			docker-php-ext-enable --ini-name "xx-php-ext-$2.ini" "$2"
			;;
		memcached)
			# memcached must be loaded after msgpack
			docker-php-ext-enable --ini-name "xx-php-ext-$2.ini" "$2"
			;;
		*)
			docker-php-ext-enable "$2"
			;;
	esac
}

# Check if a string is in a list of space-separated string
#
# Arguments:
#   $1: the string to be checked
#   $2: the string list
#
# Return:
#   0 (true): if the string is in the list
#   1 (false): if the string is not in the list
stringInList() {
	for stringInList_listItem in $2; do
		if test "$1" = "$stringInList_listItem"; then
			return 0
		fi
	done
	return 1
}

# Remove a word from a space-separated list
#
# Arguments:
#   $1: the word to be removed
#   $2: the string list
#
# Output:
#   The list without the word
removeStringFromList() {
	removeStringFromList_result=''
	for removeStringFromList_listItem in $2; do
		if test "$1" != "$removeStringFromList_listItem"; then
			if test -z "$removeStringFromList_result"; then
				removeStringFromList_result="$removeStringFromList_listItem"
			else
				removeStringFromList_result="$removeStringFromList_result $removeStringFromList_listItem"
			fi
		fi
	done
	printf '%s' "$removeStringFromList_result"
}

# Cleanup everything at the end of the execution
cleanup() {
	if test -n "$UNNEEDED_PACKAGE_LINKS"; then
		printf '### REMOVING UNNEEDED PACKAGE LINKS ###\n'
		for cleanup_link in $UNNEEDED_PACKAGE_LINKS; do
			if test -L "$cleanup_link"; then
				rm -f "$cleanup_link"
			fi
		done
	fi
	if test -n "$PACKAGES_VOLATILE"; then
		printf '### REMOVING UNNEEDED PACKAGES ###\n'
		case "$DISTRO" in
			alpine)
				apk del --purge $PACKAGES_VOLATILE
				;;
			debian)
				DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y $PACKAGES_VOLATILE
				;;
		esac
	fi
	if test -n "$PACKAGES_PREVIOUS"; then
		case "$DISTRO" in
			debian)
				printf '### RESTORING PREVIOUSLY INSTALLED PACKAGES ###\n'
				DEBIAN_FRONTEND=noninteractive apt-get install --no-upgrade -qqy $PACKAGES_PREVIOUS
				;;
		esac
	fi
	case "$DISTRO" in
		alpine)
			rm -rf /var/cache/apk/*
			;;
		debian)
			rm -rf /var/lib/apt/lists/*
			;;
	esac
	docker-php-source delete
	rm -rf /tmp/pear
	rm -rf /tmp/src
}

resetIFS
mkdir -p /tmp/src
IPE_ERRFLAG_FILE="$(mktemp -p /tmp/src)"
setDistro
setPHPMajorMinor
case "$PHP_MAJMIN_VERSION" in
	505 | 506 | 700 | 701 | 702 | 703 | 704) ;;
	*)
		printf "### ERROR: Unsupported PHP version: %s.%s ###\n" $((PHP_MAJMIN_VERSION / 100)) $((PHP_MAJMIN_VERSION % 100))
		;;
esac
UNNEEDED_PACKAGE_LINKS=''
processCommandArguments "$@"

if test -z "$PHP_MODULES_TO_INSTALL"; then
	exit 0
fi

sortModulesToInstall

buildRequiredPackageLists $PHP_MAJMIN_VERSION $PHP_MODULES_TO_INSTALL
if test -n "$PACKAGES_PERSISTENT$PACKAGES_VOLATILE"; then
	installRequiredPackages
fi
docker-php-source extract
BUNDLED_MODULES="$(find /usr/src/php/ext -mindepth 2 -maxdepth 2 -type f -name 'config.m4' | xargs -n1 dirname | xargs -n1 basename | xargs)"
for PHP_MODULE_TO_INSTALL in $PHP_MODULES_TO_INSTALL; do
	if stringInList "$PHP_MODULE_TO_INSTALL" "$BUNDLED_MODULES"; then
		installBundledModule $PHP_MAJMIN_VERSION "$PHP_MODULE_TO_INSTALL"
	else
		MODULE_SOURCE=''
		MODULE_SOURCE_CONFIGOPTIONS=''
		MODULE_SOURCE_CFLAGS=''
		case "$PHP_MODULE_TO_INSTALL" in
			cmark)
				MODULE_SOURCE=https://github.com/krakjoe/cmark/archive/v1.0.0.tar.gz
				cd "$(getPackageSource https://github.com/commonmark/cmark/archive/0.28.3.tar.gz)"
				make install
				cd - >/dev/null
				MODULE_SOURCE_CONFIGOPTIONS=--with-cmark
				;;
			snuffleupagus)
				MODULE_SOURCE="https://codeload.github.com/jvoisin/snuffleupagus/tar.gz/v0.5.0"
				MODULE_SOURCE_CONFIGOPTIONS=--enable-snuffleupagus
				;;
		esac
		if test -n "$MODULE_SOURCE"; then
			installModuleFromSource "$PHP_MODULE_TO_INSTALL" "$MODULE_SOURCE" "$MODULE_SOURCE_CONFIGOPTIONS" "$MODULE_SOURCE_CFLAGS"
		else
			installPECLModule $PHP_MAJMIN_VERSION "$PHP_MODULE_TO_INSTALL"
		fi
	fi
done
cleanup