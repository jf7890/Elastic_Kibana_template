#!/usr/bin/env bash

# Log a message.
function log {
	echo "[+] $1"
}

# Log a message at a sub-level.
function sublog {
	echo "   - $1"
}

# Log an error.
function err {
	echo "[x] $1" >&2
}

# Log an error at a sub-level.
function suberr {
	echo "   ! $1" >&2
}

# Return the Elasticsearch base URL used by setup.
function elasticsearch_url {
	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"
	local elasticsearch_scheme="${ELASTICSEARCH_SCHEME:-https}"

	echo "${elasticsearch_scheme}://${elasticsearch_host}:9200"
}

# Append the authentication and TLS flags required for Elasticsearch curl calls.
function add_elasticsearch_curl_args {
	local -n args_ref=$1
	local elasticsearch_ca="${ELASTICSEARCH_CA:-/certs/ca.crt}"

	if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
		args_ref+=( '-u' "elastic:${ELASTIC_PASSWORD}" )
	fi

	if [[ -f "${elasticsearch_ca}" ]]; then
		args_ref+=( '--cacert' "${elasticsearch_ca}" )
	elif [[ "${ELASTICSEARCH_INSECURE:-0}" == "1" ]]; then
		args_ref+=( '-k' )
	fi
}

# Poll the 'elasticsearch' service until it responds with HTTP code 200.
function wait_for_elasticsearch {
	local elasticsearch_base_url
	elasticsearch_base_url="$(elasticsearch_url)"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}' "${elasticsearch_base_url}/" )
	add_elasticsearch_curl_args args

	local -i result=1
	local output

	# retry for max 300s (60*5s)
	for _ in $(seq 1 60); do
		local -i exit_code=0
		output="$(curl "${args[@]}")" || exit_code=$?

		if ((exit_code)); then
			result=$exit_code
		fi

		if [[ "${output: -3}" -eq 200 ]]; then
			result=0
			break
		fi

		sleep 5
	done

	if ((result)) && [[ "${output: -3}" -ne 000 ]]; then
		echo -e "\n${output::-3}"
	fi

	return $result
}

# Poll the Elasticsearch users API until it returns users.
function wait_for_builtin_users {
	local elasticsearch_base_url
	elasticsearch_base_url="$(elasticsearch_url)"

	local -a args=( '-s' '-D-' '-m15' "${elasticsearch_base_url}/_security/user?pretty" )
	add_elasticsearch_curl_args args

	local -i result=1

	local line
	local -i exit_code
	local -i num_users

	# retry for max 30s (30*1s)
	for _ in $(seq 1 30); do
		num_users=0

		# read exits with a non-zero code if the last read input doesn't end
		# with a newline character. The printf without newline that follows the
		# curl command ensures that the final input not only contains curl's
		# exit code, but causes read to fail so we can capture the return value.
		# Ref. https://unix.stackexchange.com/a/176703/152409
		while IFS= read -r line || ! exit_code="$line"; do
			if [[ "$line" =~ _reserved.+true ]]; then
				(( num_users++ ))
			fi
		done < <(curl "${args[@]}"; printf '%s' "$?")

		if ((exit_code)); then
			result=$exit_code
		fi

		# we expect more than just the 'elastic' user in the result
		if (( num_users > 1 )); then
			result=0
			break
		fi

		sleep 1
	done

	return $result
}

# Verify that the given Elasticsearch user exists.
function check_user_exists {
	local username=$1

	local elasticsearch_base_url
	elasticsearch_base_url="$(elasticsearch_url)"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${elasticsearch_base_url}/_security/user/${username}"
		)
	add_elasticsearch_curl_args args

	local -i result=1
	local -i exists=0
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 || "${output: -3}" -eq 404 ]]; then
		result=0
	fi
	if [[ "${output: -3}" -eq 200 ]]; then
		exists=1
	fi

	if ((result)); then
		echo -e "\n${output::-3}"
	else
		echo "$exists"
	fi

	return $result
}

# Set password of a given Elasticsearch user.
function set_user_password {
	local username=$1
	local password=$2

	local elasticsearch_base_url
	elasticsearch_base_url="$(elasticsearch_url)"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${elasticsearch_base_url}/_security/user/${username}/_password"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\" : \"${password}\"}"
		)
	add_elasticsearch_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Create the given Elasticsearch user.
function create_user {
	local username=$1
	local password=$2
	local role=$3

	local elasticsearch_base_url
	elasticsearch_base_url="$(elasticsearch_url)"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${elasticsearch_base_url}/_security/user/${username}"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\":\"${password}\",\"roles\":[\"${role}\"]}"
		)
	add_elasticsearch_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Ensure that the given Elasticsearch role is up-to-date, create it if required.
function ensure_role {
	local name=$1
	local body=$2

	local elasticsearch_base_url
	elasticsearch_base_url="$(elasticsearch_url)"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${elasticsearch_base_url}/_security/role/${name}"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "$body"
		)
	add_elasticsearch_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}
