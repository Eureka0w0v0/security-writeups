#!/usr/bin/env bash
# Download one password-protected sample archive from MalwareBazaar into /srv/cases/<case-id>/.
# The archive is NOT extracted here: extract it only after the VM is switched to Host Only.
#   bash fetch-sample.sh <tag> <file-name-regex> <case-id>
# Example (newest ELF whose signature or tags mention "mirai" and whose file name mentions arm):
#   bash fetch-sample.sh mirai arm case01
# The Auth-Key is read from the terminal without echo and never written to disk or argv.
set -euo pipefail

readonly API="https://mb-api.abuse.ch/api/v1/"
readonly CASES_DIR="/srv/cases"
readonly QUERY_LIMIT=100

usage() {
  echo "usage: bash $0 <tag> <file-name-regex> <case-id>" >&2
  exit 2
}

# POST to the API with the key passed through curl's config on stdin (not argv).
# Writes the response body to <out>; on an HTTP error, prints the API's reason and fails.
api_post() {
  local key=$1 out=$2 code
  shift 2
  code=$(printf 'header = "Auth-Key: %s"\n' "$key" |
    curl -sS --max-time 120 -K - -X POST -o "$out" -w '%{http_code}' "$@" "$API")
  if [[ $code != 200 ]]; then
    echo "MalwareBazaar API returned HTTP $code: $(jq -r '.query_status // empty' "$out" 2>/dev/null || head -c 200 "$out")" >&2
    case $code in
      401) echo "hint: no Auth-Key was sent" >&2 ;;
      403) echo "hint: the Auth-Key was not recognised; copy it again from your abuse.ch profile" >&2 ;;
    esac
    return 1
  fi
}

# Listing queries, cheapest first. Big tags such as "mirai" can make get_taginfo exceed
# the API's execution-time limit, so it only runs last and with a small limit.
run_listing_query() {
  local key=$1 tag=$2 out=$3 n=$4
  case $n in
    1) api_post "$key" "$out" -d "query=get_recent" -d "selector=100" ;;
    2) api_post "$key" "$out" -d "query=get_file_type" -d "file_type=elf" -d "limit=$QUERY_LIMIT" ;;
    3) api_post "$key" "$out" -d "query=get_taginfo" --data-urlencode "tag=$tag" -d "limit=25" ;;
  esac
}

# Prints the SHA-256 of the first ELF whose signature or tags match <tag> and whose
# file name matches <pattern>; keeps the listing it came from in <out>.
find_sample() {
  local key=$1 tag=$2 pattern=$3 out=$4 n sha
  for n in 1 2 3; do
    run_listing_query "$key" "$tag" "$out" "$n" || return 1
    if ! jq -e '.query_status == "ok"' "$out" >/dev/null; then
      echo "listing query $n skipped: $(jq -r '[.query_status, (.data | strings)] | join(": ")' "$out")" >&2
      continue
    fi
    sha=$(jq -r --arg tag "$tag" --arg re "$pattern" '
      [.data[] | select(.file_type == "elf"
                        and (((.signature // "") | test($tag; "i")) or any((.tags // [])[]; test($tag; "i")))
                        and ((.file_name // "") | test($re; "i")))][0].sha256_hash // empty' "$out")
    if [[ -n $sha ]]; then
      echo "$sha"
      return 0
    fi
    echo "listing query $n: no match" >&2
  done
}

main() {
  [[ $# -eq 3 ]] || usage
  local tag=$1 pattern=$2 case_id=$3 key dir sha
  [[ $case_id =~ ^[A-Za-z0-9_-]+$ ]] || { echo "case-id may contain letters, digits, - and _ only" >&2; exit 2; }
  dir="$CASES_DIR/$case_id"
  mkdir -p "$dir"

  read -rsp "MalwareBazaar Auth-Key: " key
  echo
  key=${key//[[:space:]]/}
  [[ -n $key ]] || { echo "no Auth-Key entered" >&2; exit 2; }

  sha=$(find_sample "$key" "$tag" "$pattern" "$dir/listing.json")
  if [[ -z $sha ]]; then
    echo "no ELF sample of '$tag' with a file name matching '$pattern' was found; try again later or loosen the pattern" >&2
    exit 1
  fi
  jq --arg s "$sha" '[.data[] | select(.sha256_hash == $s)][0]' "$dir/listing.json" > "$dir/metadata.json"
  echo "$sha" > "$dir/expected-sha256.txt"

  api_post "$key" "$dir/sample.zip" --data-urlencode "query=get_file" --data-urlencode "sha256_hash=$sha"
  unset key
  if [[ $(head -c 2 "$dir/sample.zip") != "PK" ]]; then
    echo "download failed: $(head -c 300 "$dir/sample.zip")" >&2
    rm -f "$dir/sample.zip"
    exit 1
  fi

  jq -r '"picked:     \(.file_name)  (signature: \(.signature // "-"), first seen \(.first_seen))\nsha256:     \(.sha256_hash)"' \
    "$dir/metadata.json"
  echo "saved:      $dir/sample.zip ($(stat -c %s "$dir/sample.zip") bytes, still encrypted)"
}

main "$@"
