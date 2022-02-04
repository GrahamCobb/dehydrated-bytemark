#!/usr/bin/env bash
#
# Dehydrated hook script to handle DNS-01 challenge using Bytemark DNS servers.
# This might also be usable with other tinydns/djbdns servers.
#
# Adapted from https://github.com/sebastiansterk/dns-01-manual/blob/master/hook.sh
# which is from https://github.com/lukas2511/dehydrated/blob/master/docs/examples/hook.sh
# And from https://github.com/bennettp123/dehydrated-email-notify-hook/blob/master/hook.sh
#

# Accessing the user's DNS account requires the following environment variables to be set.
#    RSYNC_USERNAME=someuser@some.email.domain
#    RSYNC_PASSWORD=super-secret-random-password
# They are provided by Bytemark (for example in the 'upload' script)
# These should be specified in an /etc/dehydrated/conf.d script

download_dns_files() {
	export RSYNC_PASSWORD
	rsync -r dns@upload.ns.bytemark.co.uk::${RSYNC_USERNAME}/ $DOMAIN_DATA_DIR/
}
upload_dns_files() {
	local DOMAIN_FILE="$1"
	export RSYNC_PASSWORD
	rsync $DOMAIN_FILE dns@upload.ns.bytemark.co.uk::${RSYNC_USERNAME}/
}
DOMAIN_RELOAD="upload_dns_files"
function has_propagated {
    while [ "$#" -ge 2 ]; do
        local RECORD_NAME="${1}"; shift
        local TOKEN_VALUE="${1}"; shift
        if [ ${#AUTH_NS[@]} -eq 0 ]; then
            local RECORD_DOMAIN=$RECORD_NAME
            declare -a iAUTH_NS
            while [ -z "$iAUTH_NS" ]; do
                RECORD_DOMAIN=$(echo "${RECORD_DOMAIN}" | cut -d'.' -f 2-)
                iAUTH_NS=($(dig +short "${RECORD_DOMAIN}" IN CNAME))
                if [ -n "$iAUTH_NS" ]; then
                    unset iAUTH_NS && declare -a iAUTH_NS
                    continue
                fi
                iAUTH_NS=($(dig +short "${RECORD_DOMAIN}" IN NS))
            done
        else
           local iAUTH_NS=("${AUTH_NS[@]}")
        fi
        for NS in "${iAUTH_NS[@]}"; do
            dig +short @"${NS}" "${RECORD_NAME}" IN TXT | grep -q "\"${TOKEN_VALUE}\"" || return 1
        done
        unset iAUTH_NS
    done
    return 0
}


find_file_for_domain() {
	local domain="$1"
	local f fname
	
	for f in $DOMAIN_DATA_DIR/*
	do
		# See if the file name matches the right hand end of the domain name
		fname=$(basename "$f")
		if [ "${domain%%$fname}" != "$domain" ]
		then
			# filename matches the end of the domain
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
	local RECORDS=() wait_time=30 max_waits=10 wait_count=0
	while [[ $# -gt 0 ]]
	do
		local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}" ; shift 3
		local domain_file=$(find_file_for_domain "$DOMAIN")
		djbdns-modify "$domain_file" remove "_acme-challenge.${DOMAIN}" TEXT
		djbdns-modify "$domain_file" add "_acme-challenge.$DOMAIN" TEXT "$TOKEN_VALUE"
		RECORDS+=( "_acme-challenge.$DOMAIN" )
		RECORDS+=( ${TOKEN_VALUE} )
	done
	$DOMAIN_RELOAD "$domain_file"

	sleep 10
	while ! has_propagated "${RECORDS[@]}"
	do
		( wait_count++ ) || true # Note: we have set -e
		[[ $wait_count -gt $max_waits ]] && return 1
		echo " + DNS not propagated. Waiting ${wait_time}s for record creation and replication..."
		sleep $wait_time
	done
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

# We need a temporary directory to download the user's Bytemark DNS files
DOMAIN_DATA_DIR=$(mktemp -d)
download_dns_files

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi

# Get rid of DNS files
rm -rf $DOMAIN_DATA_DIR

