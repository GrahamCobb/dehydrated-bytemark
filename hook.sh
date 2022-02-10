#!/usr/bin/env bash
#
# Dehydrated hook script to handle DNS-01 challenge using Bytemark DNS servers.
# This might also be usable with other tinydns/djbdns servers.
#
# NOTE: this script assumes that if no dns data file can be found for the domain,
# the user should be prompted to deploy the challenge manually (for example,
# using a registrar's web interface).
#
# Adapted from https://github.com/sebastiansterk/dns-01-manual/blob/master/hook.sh
# which is from https://github.com/lukas2511/dehydrated/blob/master/docs/examples/hook.sh
# And inspired by https://github.com/bennettp123/dehydrated-email-notify-hook/blob/master/hook.sh
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
#
# has_propagated takes a list of DNS names and corresponding TEXT values:
#  <name> <text> [<name> <text>]...
# It checks that all the names are defined, on all the authoritative servers, with the specified TEXT.
# If any of the values are wrong, or the name is not defined, on any server then it returns false.
#
# Note: retrying and waiting are the responsibility of the caller.
#
# A future optimisation might retain the list of authorative servers to save some lookups.
#
has_propagated() {
	while [[ $# -gt 0 ]]
	do
		unset AUTH_NS || true # Ignore error in set -e environment
		local name="$1" value="$2" ; shift 2
		local AUTH_NS=$(get_authoritative_ns $name) || { echo "Cannot determine authoritative nameservers for $name" ; return 2 ; }
		for NS in $AUTH_NS
		do
			dig +short @"$NS" "$name" IN TXT | fgrep -q "$value" || return 1	
		done
	done

	# All OK
	return 0
}
#
# In general, there is no way to work out the "domain" part of an arbitrary DNS name.
# So, get_authoritative_ns starts with the full DNS name and strips leading components
# off until it gets the nameserver(s)
get_authoritative_ns() {
	local name="$1"
	local nslist

	# Add trailing dot if omitted
	[[ "${name%.}" == "$name" ]] && name="${name}."

	while [[ "$name" != "" ]]
	do
		# Need to first follow any CNAME
		cname="$(dig +short "$name" IN CNAME)"
		if [[ "${#cname}" -gt 0 ]]
		then
			name="$cname"
			[[ "${name%.}" == "$name" ]] && name="${name}."
			continue
		fi
				
		nslist="$(dig +short "$name" IN NS)"
		[[ "${#nslist}" -gt 0 ]] && echo "$nslist" && return 0
		name="${name#*.}"
	done

	# No nameservers found!
	return 2
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
	local RECORDS=() wait_time=60 max_waits=10 wait_count=0
	while [[ $# -gt 0 ]]
	do
		local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}" ; shift 3
		local domain_file=$(find_file_for_domain "$DOMAIN")
		if [[ "${#domain_file}" -eq 0 ]]
                then
                  echo "No djbdns file found for domain $DOMAIN"
                  echo ""
                  echo "To deploy the challenge manually:"
                  echo "Create or modify the DNS name _acme-challenge.${DOMAIN} to have"
                  echo "the TXT value $TOKEN_VALUE"
                  echo ""
                  echo "Then press RETURN below."
                  echo ""
                  echo "If this cannot be done, enter N and press return - this will abort the challenge"
                  echo ""
                  echo -n "Have you added _acme-challenge.$DOMAIN: $TOKEN_VALUE ? ([Y]/N) "
                  read DONE
                  [[ "$DONE" == "N" || "$DONE" == "n" ]] && return 1
                else
                  # Note: this previously removed all existing _acme-challenge. TEXT records
                  # but that is incorrect as the same challenge may require multiple token for the same domain
		  djbdns-modify "$domain_file" add "_acme-challenge.$DOMAIN" TEXT "$TOKEN_VALUE"
		  echo "Added _acme-challenge.$DOMAIN: $TOKEN_VALUE"
		  $DOMAIN_RELOAD "$domain_file"
                fi

		RECORDS+=( "_acme-challenge.$DOMAIN" )
		RECORDS+=( ${TOKEN_VALUE} )
	done

	# Bytemark DNS normally takes about 5 mins to propagate.
	sleep $wait_time
	while ! has_propagated "${RECORDS[@]}"
	do
		(( wait_count++ )) || true # Note: we have set -e
		[[ $wait_count -gt $max_waits ]] && return 1
		echo " + DNS not propagated. Waiting ${wait_time}s for record creation and replication..."
		sleep $wait_time
	done
        return 0
}

clean_challenge() {
	while [[ $# -gt 0 ]]
	do
		local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}" ; shift 3
		local domain_file=$(find_file_for_domain "$DOMAIN")
		if [[ "${#domain_file}" -eq 0 ]]
                then
                  echo "No djbdns file found for domain $DOMAIN"
                  echo ""
                  echo "To clean up the challenge manually:"
                  echo "Remove the DNS name _acme-challenge.${DOMAIN}"
                  echo "Then press RETURN below."
                  echo ""
                  echo "If this cannot be done, enter N and press return - this will abort the challenge"
                  echo ""
                  echo -n "Have you removed _acme-challenge.$DOMAIN: $TOKEN_VALUE ? ([Y]/N) "
                  read DONE
                  [[ "$DONE" == "N" || "$DONE" == "n" ]] && return 1
                else
                  djbdns-modify "$domain_file" remove "_acme-challenge.$DOMAIN" TEXT "$TOKEN_VALUE"
		  echo "Removed _acme-challenge.$DOMAIN: $TOKEN_VALUE"
		  $DOMAIN_RELOAD "$domain_file"
                fi
	done
        return 0
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

