#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# This bash script is used to authenticate with Google's OAuth2 service.
# and generate/refresh access tokens
#
#author : Saeed Mahameed <saeed@kernel.org>

default_scope="https://mail.google.com/"
default_port=8088
default_browser="firefox"
default_store="$HOME/.var/g-oauth2/"

function usage {
	echo "Usage: $0 --option=value ..."
	echo ""
	echo "Optains google oauth2 tokens and caches it: "
	echo "  Silently dumps the access token to stdout, even on intitial authenication."
	echo "  Useful as 'PassCmd' commands for apps that require oauth2 authentication"
	echo "  Example: $0 --client_id=123456789.apps.googleusercontent.com --client_secret=abcdefg"
	echo ""
	echo "Options:"
	echo "  --client-id      : Client ID"
	echo "  --client-secret  : Client Secret"
	echo "  --login          : Login Hint, optional (email)"
	echo "  --scope          : Scope (default: $default_scope)"
	echo "  --port           : Port (default: $default_port)"
	echo "  --browser        : Browser (default: $default_browser)"
	echo "  --store          : Directory to cache token files (default: $default_store)"
	echo "  --help           : This help"
	echo ""
	echo "Output: access_token"
}

ALL_ARGS=$*

get_flag () {
	[ $(echo "$ALL_ARGS" | grep -oPe "--${1}") ] && return 0
	return 1
}
# --option=value // NO SPACES ALLOWED, keep values simple
get_arg () { echo $ALL_ARGS | grep -oPe "--${1}=\s*\K[^\s]*" || true; }

get_flag help && usage && exit 0

CLIENT_ID=$(get_arg client_id)
CLIENT_SECRET=$(get_arg client_secret)
LPORT=$(get_arg port); LPORT=${LPORT:-8088}
STORE=$(get_arg store);STORE=${STORE:-$default_store}
BROWSER=$(get_arg browser);BROWSER=${BROWSER:-$default_browser}
SCOPE=$(get_arg scope);SCOPE=${SCOPE:-$default_scope}
LOGIN_HINT=$(get_arg login)

[ -z "$CLIENT_ID" ] && echo "Missing: client-id" && usage && exit 1
[ -z "$CLIENT_SECRET" ] && echo "Missing: client-secret" && usage && exit 1

redirect_uri="http://localhost:${LPORT}"

mkdir -p $STORE

function cleanup {
	rm -rf $STORE/fifo  > /dev/null 2>&1
	[ ! -z $NCPID ] && kill -9 $NCPID  > /dev/null 2>&1
}

# listens to redirect uri
function setup_auth_code_listener {
	rm -rf $STORE/fifo;	mkfifo $STORE/fifo

	nc -kp ${LPORT} -l > $STORE/fifo &
	NCPID=$!

	trap cleanup EXIT
}

function wait_for_auth_code {
	# Code must be in the first line
	read -t 60 line < $STORE/fifo
	if [[ $line == *"code="* ]]; then
		# extract code
		code=$(echo $line | grep -oP 'code=\K[^&]*')
		[ -z "$code" ] && echo "failed to extract code: resp: $line" && exit 1
		echo $code > $STORE/auth_code
		( sleep 0.2; kill -9 $NCPID &> /dev/null ) &
		wait $NCPID; unset NCPID
	else
		echo "Failed to get auth code"
		echo $line
		exit 1
	fi
}

function get_access_code {
	[ -f $STORE/auth_code ] || return
	cat $STORE/auth_code
}

function get_refresh_token
{
	file=$1 && [ -f $file ] || return
	# "//empty": return empty string instead of null when no match
	jq -r '.refresh_token //empty' $file
}

function check_expired
{
	file=$1; [ -f $file ] || return 1
	ftime=$(stat -c %Y $file)
	exp=$(jq -r '.expires_in //empty' $file)
	[ -z "$exp" ] && return 1
	expires_at=$(( $ftime + $exp ))
	now=$(date +%s); [ $now -gt $expires_at ] && return 1
	return 0
}

function get_access_token
{
	file=$1; [ -f $file ] || return
	check_expired $file || return
	jq -r '.access_token //empty' $file
}

function fetch_auth_code {
	setup_auth_code_listener

	# URL="https://accounts.google.com/o/oauth2/auth?"
	URL='https://accounts.google.com/o/oauth2/v2/auth?'
	URL+="client_id=$CLIENT_ID"
	URL+="&redirect_uri=$redirect_uri"
	URL+="&scope=$SCOPE"
	URL+="&response_type=code"
	URL+="&access_type=offline"
	[ $LOGIN_HINT ] && URL+="&login_hint=$LOGIN_HINT"

	$BROWSER "$URL"
	wait_for_auth_code
}

function fetch_refresh_token {
	auth_code=$(get_access_code)
	[ -z "$auth_code" ] && return 1

	DATA="client_id=$CLIENT_ID"
	DATA+="&client_secret=$CLIENT_SECRET"
	DATA+="&redirect_uri=$redirect_uri"
	DATA+="&code=$auth_code"
	DATA+="&grant_type=authorization_code"

	curl -s -X POST --data "$DATA" https://accounts.google.com/o/oauth2/token > $STORE/refresh_token
}

function fetch_access_token {
	refresh_token=$(get_refresh_token $STORE/refresh_token)
	[ -z "$refresh_token" ] && return 1

	DATA="client_id=$CLIENT_ID"
	DATA+="&client_secret=$CLIENT_SECRET"
	DATA+="&refresh_token=$refresh_token"
	DATA+="&grant_type=refresh_token"

	curl -s -X POST --data "$DATA" https://accounts.google.com/o/oauth2/token > $STORE/access_token
}

access_token=$(get_access_token $STORE/refresh_token)
[ -z "$access_token" ] && access_token=$(get_access_token $STORE/access_token)

[ -z "$access_token" ] && {
	# no token/expired ? try refresh, refresh tokens are valid for 6 months
	fetch_access_token
	access_token=$(get_access_token $STORE/access_token)
}

[ -z "$access_token" ] && {
	# still no token ? re-authenticate, new code
	fetch_auth_code > /dev/null 2>&1
	fetch_refresh_token && fetch_access_token
	access_token=$(get_access_token $STORE/access_token)
}

echo $access_token
