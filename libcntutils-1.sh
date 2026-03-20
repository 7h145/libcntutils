#!/bin/bash
# vim:et:ai:sw=2:tw=0:ft=bash
#
# libcntutils-1.sh - bash(1) library, small podman-run(1) helpers
# copyright 2026 <github.attic@typedef.net>, CC BY 4.0

#set -vx; set -o functrace
set -o pipefail

IAM="${IAM:-${0##*/}}"

libcntutils.version() {
  # This is intended to be overridden with a "real" version() function.

  local VERSION x
  read -r VERSION x < <(sha1sum "${0}") # take that semver!
  [ -n "${VERSION}" ] && echo "${IAM} version ${VERSION}"
}

libcntutils.serialize() {
  # $*: array variable names.  Print the values of the arrays $*, one
  # value per line.

  local ARGV; for ARGV in "${@}"; do
    declare -n ARRAY="${ARGV}"
    (( "${#ARRAY[@]}" > 0 )) && printf '%s\n' "${ARRAY[@]}"
  done
}

libcntutils.datemark() {
  # Read lines from stdin, add a custom prefix to each line of input and
  # print the line to stdout (somewhat like ts(1), typically packaged in
  # 'moreutils').

  local LINE HOST="${HOSTNAME:-$(hostname -s)}" IAM="${CNAME:-${IAM}}"
  local LINE; while read -r LINE; do
    [ -n "${LINE}" ] && printf '%s %s %s[%d]: %s\n' \
      "$(date --rfc-3339=s)" "${HOST}" "${IAM}" "${$}" "${LINE}"
  done
}

libcntutils.randompassword() {
  # $1: unset or number of random character to generate, default is 16.
  # Print a random string of characters from [:allnum:] of length $1.

  printf '%s\n' \
    "$(LC_ALL=C tr -dc '[:alnum:]' </dev/urandom |head -c "${1:-16}")"
}

libcntutils.stringtodecimal() {
  # Convert stdin bytes to integers, concatenate.

  [ ! -t '0' ] && od -v -A none -t d1 |tr -dc '[:alnum:]'
}

libcntutils.mapint16(){
  # $*: seed value.  Write a stable "hash-like" mapping of the seed
  # value $* into the 16bit integer range 0,..,2^16-1.

  local SEED="${*:?}"; read -r SEED x < <(md5sum <<<"${SEED}")

  # Get 5 digits of OFFSET from the decimal representation of SEED
  declare -i OFFSET="$(( "$(stringtodecimal <<<"${SEED}" |head -c5)" ))"

  # Map OFFSET into 0,..,2^16-1
  echo "$(( OFFSET % 2**16 ))"
}

libcntutils.accessibleport(){
  # $*: seed value.  Map to 14bit integer range 49152,...,65535.
  # General idea: these ports are accessible on the host.

  declare -i OFFSET="$(mapint16 "${*:?}")"

  # Map OFFSET into the last 2^14 block of the 2^16 port range
  echo "$(( 2**15 + 2**14 + OFFSET % 2**14 ))"
}

libcntutils.protectedport() {
  # $*: seed value.  Map to 14bit integer range 32768,...,49151.
  # General idea: these ports are protected on the host.

  declare -i OFFSET="$(mapint16 "${*:?}")"

  # Map OFFSET into the second-to-last 2^14 block of the 2^16 port range
  echo "$(( 2**15 + OFFSET % 2**14 ))"
}

libcntutils.addarray() {
  # $1: indexed array name, $2... array values to add to the array $1.

  declare -n ARRAY="${1:?}"; shift; [[ -v ARRAY ]] || declare -ga ARRAY
  local VALUE; for VALUE in "${@}"; do ARRAY+=( "${VALUE}" ); done
}

libcntutils.setenv() {
  # $1: podmane-run(1) '--env' variable name, $2... variable value.
  # Just a fancy curried version of addarray() for $PMARGS_ENV.

  local KEY="${1:?}"; shift; local VALUE="${*}"
  [[ -z "${VALUE}" && -v "${KEY}" ]] && VALUE="${!KEY}"
  addarray PMARGS_ENV '--env' "${KEY}=${VALUE}"
}

libcntutils.clean() {
  # $1: unset or a bash glob pattern, $2: unset or replacement string.
  # Remove characters matching the pattern $1 from lines of stdin,
  # optionally replacing them with the replacement string $2.

  local ALLOWED="${1:-[:alnum:]}" REPLACEMENT="${2}"
  local LC_ALL='C'		# YMMV

  [[ ! -t '0' ]] || return; declare -a INPUT; mapfile -t INPUT

  local i; for (( i=0; i<${#INPUT[@]}; i++ )); do
    INPUT[i]="${INPUT[i]#${INPUT[i]%%[${ALLOWED}]*}}"		# remove leading
    INPUT[i]="${INPUT[i]%${INPUT[i]##*[${ALLOWED}]}}"		# remove trailing
    INPUT[i]="${INPUT[i]//[!${ALLOWED}]/${REPLACEMENT}}"	# replace
  done

  [[ -n "${INPUT}" ]] && { IFS=$'\n'; echo "${INPUT[*]}"; }
}

libcntutils.fclean() {
  # $1: some probably unsafe "file name like" string.  Output a file
  # name safe version of $1.

  local INPUT="${*:?}"
  clean '[:alnum:]_+-' '_' <<<"${INPUT}"
}

libcntutils.regrepo() {
  # $1: regex(7) regular expression.  Read a single line of input from
  # stdin, regex(3)-match the regular expression $1 against the line of
  # input.  Return the first matched string (kind of like 'grep -o').

  [[ ! -t '0' ]] || return; local INPUT; read -r INPUT
  [[ "${INPUT}" =~ ${1:?} ]] && echo "${BASH_REMATCH}"
}

libcntutils.rematch() {
  # $*: regex(7) regular expressions.  Read a single line of input from
  # stdin, regex(3)-match the disjunction of the regular expressions $*
  # against the line of input.  Return the first matched string.

  local RE; printf -v RE '(%s)' "$(IFS='|'; echo "${*:?}")"

  [[ ! -t '0' ]] || return; regrepo "${RE}"
}

libcntutils.imagetitlebyocilabel() {
  # $1: image name (with or without tag).  Read the title of the image
  # from the OCI 'org.opencontainers.image.title' label.  This would be
  # nice, if it were widely supported.
  # See https://specs.opencontainers.org/image-spec/annotations.

  local IMAGE="${1:?}"

  # is this image in local storage?
  [[ -n "$(podman image list --quiet "${IMAGE}")" ]] || return 1

  [[ "${IMAGE}" = "${IMAGE%:*}" ]] && {
    declare -a IMAGETAGS; mapfile -t IMAGETAGS < <(
      podman image list --format '{{.Tag}}' "${IMAGE}" 2>&-)

    [[ -n "${IMAGETAGS}" ]] && IMAGE+=":${IMAGETAGS}"
  }

  local TITLE; read -r TITLE < <(
    podman image inspect -f json "${IMAGE}" |\
      jq -r '.[].Config.Labels."org.opencontainers.image.title"')

  [[ -n "${TITLE}" && "${TITLE}" != 'null' ]] && echo "${TITLE,,}"
}

libcntutils.imagetitlebymatch() {
  # $1: image name, $2... unset or image title candidates.  Guess the
  # title of the image as the trailing component of the repository of
  # the image name $1.  If a list of candidate titles $2... is given,
  # match the candidates against the guessed title.  Wonky.

  local IMAGE="${1:?}"; shift; IMAGE="${IMAGE%:*}"
  local TITLE="${IMAGE##*/}"

  # in the absence of candidates, just match literally (i.e. '.*')
  rematch "${@:-.*}" <<<"${TITLE}"
}

libcntutils.imagetitle() {
  # $1: image name, $2... unset or further imagetitle...() parameters.
  # Guess the title of the image $1.

  local IMAGETITLE

  # Select an imagetitle...() function to use.  Maybe fancy logic later.
  #IMAGETITLE="$(imagetitlebyocilabel "${@}")"
  IMAGETITLE="$(imagetitlebymatch "${@}")"

  [[ -n "${IMAGETITLE}" ]] && fclean "${IMAGETITLE}"
}

libcntutils.containerid() {
  # $1: image name, $2...: unset or container identifier(s).  Generate
  # an container id from the image title and the identifier(s) $2...

  local IMAGE="${1:?}"; shift

  fclean "$(imagetitle "${IMAGE}")${1:+-${*}})"
}

libcntutils.showpublish() {
  # $1: indexed array name.  Assume the array $1 contains podman-run(1)
  # '--publish' arguments; print a concise representation to stdout.

  declare -n ARRAY="${1:?}"; [[ -n "${ARRAY}" ]] || return 1
  declare -a PORTMAP; local PORTMAPSTRING

  PORTMAP=( "${ARRAY[@]#--publish}" ); PORTMAP=( ${PORTMAP[*]} )
  PORTMAPSTRING="$(IFS=','; echo "${PORTMAP[*]}")"

  echo "will publish: ${PORTMAPSTRING//,/, }"
}


# functions declared in this library, determined by name prefix
declare -a LIBFUNCS
mapfile -t LIBFUNCS < <(compgen -A function 'libcntutils.')

# use/export the library function if it's not already declared
for FUNC in "${LIBFUNCS[@]}"; do
  [[ -n "$(type -t "${FUNC#'libcntutils.'}")" ]] ||
    eval "${FUNC#'libcntutils.'}() { ${FUNC} \"\${@}\"; }"
done

# we may be executed instead of being sourced
case "${IAM}" in 'libcntutils-'*)
  CMD="libcntutils.${1#'libcntutils.'}"; shift
  [ "$(type -t "${CMD}" )" = 'function' ] && "${CMD}" "${@}"
;; esac

