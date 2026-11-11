#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_gyro_info='Gyro DNS (GyroHosting.com)
Site: gyrohosting.com/developers
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_gyro
Options:
 GYRO_Token ACME key. Create it in the Gyro DNS service page, ACME / Let'"'"'s Encrypt section. The key can only manage _acme-challenge TXT records.
OptionsAlt:
 GYRO_Api API base URL. Default "https://www.gyrohosting.com/api/v1/client/".
Issues: github.com/acmesh-official/acme.sh/issues/7398
Author: Gyro Hosting <https://github.com/Gyro-Hosting>
'

GYRO_Api_Default="https://www.gyrohosting.com/api/v1/client/"

########  Public functions #####################

# Usage: dns_gyro_add _acme-challenge.www.example.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gyro_add() {
  fulldomain=$1
  txtvalue=$2
  _gyro_init || return 1
  _info "Adding TXT record to Gyro DNS"
  _debug fulldomain "$fulldomain"
  if ! _gyro_rest POST "cloud/dns/acme-challenge" "{\"name\":\"$fulldomain\",\"value\":\"$txtvalue\"}"; then
    _err "Could not add the TXT record: $response"
    return 1
  fi
  # Wait until both authoritative name servers publish the value (normally < 1 minute).
  _gyro_i=0
  while [ "$_gyro_i" -lt 36 ]; do
    if _gyro_rest GET "cloud/dns/acme-challenge?name=$fulldomain&value=$txtvalue" && _contains "$response" '"ready":true'; then
      _info "TXT record is live on Gyro DNS name servers"
      return 0
    fi
    _gyro_i=$(_math "$_gyro_i" + 1)
    _sleep 5
  done
  _info "TXT record added; name servers have not confirmed yet, continuing"
  return 0
}

# Usage: dns_gyro_rm _acme-challenge.www.example.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gyro_rm() {
  fulldomain=$1
  txtvalue=$2
  _gyro_init || return 1
  _info "Removing TXT record from Gyro DNS"
  if ! _gyro_rest DELETE "cloud/dns/acme-challenge?name=$fulldomain&value=$txtvalue"; then
    _err "Could not remove the TXT record: $response"
    return 1
  fi
  return 0
}

####################  Private functions below ##################################

_gyro_init() {
  GYRO_Token="${GYRO_Token:-$(_readaccountconf_mutable GYRO_Token)}"
  GYRO_Api="${GYRO_Api:-$(_readaccountconf_mutable GYRO_Api)}"
  if [ -z "$GYRO_Token" ]; then
    GYRO_Token=""
    _err "You did not specify GYRO_Token (your Gyro DNS ACME key)."
    _err "Create one in the Gyro DNS service page > ACME / Let's Encrypt, then: export GYRO_Token=\"wck_...\""
    return 1
  fi
  _saveaccountconf_mutable GYRO_Token "$GYRO_Token"
  if [ -n "$GYRO_Api" ] && [ "$GYRO_Api" != "$GYRO_Api_Default" ]; then
    _saveaccountconf_mutable GYRO_Api "$GYRO_Api"
  else
    GYRO_Api="$GYRO_Api_Default"
  fi
  return 0
}

# _gyro_rest METHOD path [json]  -> sets $response, returns 0 on HTTP 2xx
_gyro_rest() {
  m=$1
  ep="$2"
  data="$3"
  export _H1="Authorization: Bearer $GYRO_Token"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"
  _debug "$m" "$ep"
  if [ "$m" = "GET" ]; then
    response="$(_get "$GYRO_Api$ep")"
  else
    response="$(_post "$data" "$GYRO_Api$ep" "" "$m")"
  fi
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    return 1
  fi
  case "$_code" in
  2*) return 0 ;;
  esac
  return 1
}
