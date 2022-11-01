#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# This bash script is used to authenticate with Microsoft's OAuth2 service for outlook
# and generate/refresh access tokens
#
#author : Saeed Mahameed <saeed@kernel.org>
#
#Link: https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow

default_scope="https://outlook.office.com/IMAP.AccessAsUser.All"
default_port=8087
default_browser="firefox"
default_store="$HOME/.var/ms-oauth2/"

function usage {
	echo "Usage: $0 --option=value ..."
	echo ""
	echo "Optains MS oauth2 tokens and caches it: "
	echo "  Silently dumps the access token to stdout, even on intitial authenication."
	echo "  Useful as 'PassCmd' commands for apps that require oauth2 authentication"
	echo "  Example: $0 --client_id=123456789"
	echo ""
	echo "Options:"
	echo "  --client-id      : Client ID"
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
LPORT=$(get_arg port); LPORT=${LPORT:-$default_port}
STORE=$(get_arg store);STORE=${STORE:-$default_store}
BROWSER=$(get_arg browser);BROWSER=${BROWSER:-$default_browser}
SCOPE=$(get_arg scope);SCOPE=${scope:-$default_scope}

[ -z "$CLIENT_ID" ] && echo "Missing: client-id" && usage && exit 1

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
		kill -9 $NCPID > /dev/null 2>&1
		unset NCPID
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

	TENANT="common"
	URL="https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/authorize?"
	URL+="client_id=$CLIENT_ID"
	URL+="&response_type=code"
	URL+="&redirect_uri=$redirect_uri"
	URL+="&response_mode=query"
	URL+="&scope=$SCOPE"
	URL+="&access_type=offline"

	#URL="http://localhost:8087/?code=0.AVsAFT0IQ3NywUC32znv2czBeiZILxL5rV1GjoTp0AvJ8jQ4AAA.AgABAAIAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P-1jPIVszWsSHdci10NtHlkLF3F6fnJil1l2KhzJMZtulKE-vesBf08WbyM6cPUbQi2-V91G0quJtWp4OruUcc16eMQ_xjVDgPVZSWUP2-YxMADQsrqRZL-V68HXtjZvPb88ztoxq7EirbfzvZzasIGDWmb5AzwOYxQ9Lw66TmQUBnmcQMCF2-KfMtX7PlMnC5UMFtxNM2s_44KFn6Nj4nRDRBHpSPsfa_m1XxySYnoGtNL-1NnWzaeJbYoqbT9aK-IgnK241tMH4opdvJ0gPndAhs5hczWqGLOd70rRoDi5XKg6PFNYUYL7_H1C8sFSwO6d-BHpMpAqBzWkPyWVdU4929OYsSI_1RSGpUHmKt-zAefqng1t4DhYegO-d9FKds07GqEJh-heEqfsk-U3TEYdMQVX0OH71S0i79Pl5NjVrY-TJC6M3KV5HaQ3rMZqg6bY4USnj7Dsj2BBul2C-u-3WycS70dIX5yrRnz0CG_NML38vt1TfkmMGpwzqghlMe5RUVygDaQqwocdmXpAuiPoy9LeGJ3U7fKMQvXVk16d6aiKTfPX1z_EbVW-vOnaEj8e9zPMhOS1DD5-gsTu27nP5AkbO6OJuZ2mgZnWAjLwjgc5BNtYSnhg9fMueek_bUWrIq2I5ZzIUFocuYJl6gKTfJO-VnD8B-whDiuI4N6mDc9k-_o9hJw&session_state=d12d6021-7097-4727-abaa-97f482dd2283"
	$BROWSER "$URL" &
	echo "waiting for auth code..."
	wait_for_auth_code
}

function fetch_refresh_token {
	auth_code=$(get_access_code)
	[ -z "$auth_code" ] && return 1

	DATA="client_id=$CLIENT_ID"
	DATA+="&scope=$SCOPE"
	DATA+="&code=$auth_code"
	#DATA+="&client_secret=$CLIENT_SECRET"
	DATA+="&redirect_uri=$redirect_uri"
	DATA+="&grant_type=authorization_code"
	DATA+="&access_type=offline" # NOTE: This is required for refresh tokens

	TENANT="common"
	URL="https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token"

	curl -s -X POST --data "$DATA" $URL > $STORE/refresh_token
}

function refresh_access_token {
	refresh_token=$(get_refresh_token $STORE/refresh_token)
	[ -z "$refresh_token" ] && return 1

	DATA="client_id=$CLIENT_ID"
	DATA+="&scope=$SCOPE"
	DATA+="&refresh_token=$refresh_token"
	DATA+="&grant_type=refresh_token"

	TENANT="common"
	URL="https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token"
	curl -s -X POST --data "$DATA" $URL > $STORE/access_token
}

# set -x # DEBUG

access_token=$(get_access_token $STORE/refresh_token)
[ -z "$access_token" ] && access_token=$(get_access_token $STORE/access_token)

[ -z "$access_token" ] && {
	# no token/expired ? try refresh, refresh tokens are valid for 24h

	# TODO: for some reason we don't get refresh tokens
	#       so the refresh flow isn't doing anything for now..
	refresh_access_token
	access_token=$(get_access_token $STORE/access_token)
}

[ -z "$access_token" ] && {
	# still no token ? re-authenticate, new code
	fetch_auth_code > /dev/null 2>&1
	fetch_refresh_token
	access_token=$(get_access_token $STORE/refresh_token)
	[ -z "$access_token" ] && {
		 refresh_access_token
		access_token=$(get_access_token $STORE/access_token)
	}
}

echo $access_token
