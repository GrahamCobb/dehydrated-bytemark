#!/usr/bin/env bash
#
# Dehydrated hook script to handle DNS-01 challenge using Bytemark DNS servers.
# This might also be usable with other tinydns/djbdns servers.
#
# Adapted from https://github.com/sebastiansterk/dns-01-manual/blob/master/hook.sh
# which is from https://github.com/lukas2511/dehydrated/blob/master/docs/examples/hook.sh
#

DOMAIN_DATA_DIR=/home/cobb/BytemarkDNS/data
DOMAIN_RELOAD=/home/cobb/BytemarkDNS/upload

find_file_for_domain() {
	local domain="$1"
	local f fname
	
	for f in $DOMAIN_DATA_DIR/*
	do
		# See if the file name matches the right hand end of the domain name
		fname=$(basename "$f")
		if [ "${fname%%$domain}" != "$fname" ]
		then
			# $domain matches the end of the filename
			# so we have found the right file
			echo "$f"
			return 0
		fi
	done
	# Not found
	return 1
}

set -eu -o pipefail

deploy_challenge() {
	local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
	local domain_file=$(find_file_for_domain "$DOMAIN")
	djbdns-modify "$domain_file" remove "_acme-challenge.${DOMAIN}" TEXT
	djbdns-modify "$domain_file" add "_acme-challenge.$DOMAIN" TEXT "$TOKEN_VALUE"
	$DOMAIN_RELOAD "$domain_file"
}

clean_challenge() {
	local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
	local domain_file=$(find_file_for_domain "$DOMAIN")
	djbdns-modify "$domain_file" remove "_acme-challenge.${DOMAIN}" TEXT "$TOKEN_VALUE"
	$DOMAIN_RELOAD "$domain_file"
}

deploy_cert() {
		local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"
		echo ""
		echo "deploy_cert()"
		echo ""
}

unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
		echo ""
		echo "unchanged_cert()"
		echo ""
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"
		echo ""
		echo "invalid_challenge()"
		echo "${1}"
		echo "${2}"
		echo ""
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}"
		echo ""
		echo "request_failure()"
		echo "${1}"
		echo "${2}"
		echo "${3}"
		echo ""
}

exit_hook() {
		echo ""
		echo "done"
		echo ""
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi
