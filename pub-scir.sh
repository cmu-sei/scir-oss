#!/bin/bash
#
# Open Source P4 Tool
# 
# Copyright 2024 Carnegie Mellon University.
# 
# NO WARRANTY. THIS CARNEGIE MELLON UNIVERSITY AND SOFTWARE ENGINEERING
# INSTITUTE MATERIAL IS FURNISHED ON AN "AS-IS" BASIS. CARNEGIE MELLON
# UNIVERSITY MAKES NO WARRANTIES OF ANY KIND, EITHER EXPRESSED OR IMPLIED, AS
# TO ANY MATTER INCLUDING, BUT NOT LIMITED TO, WARRANTY OF FITNESS FOR PURPOSE
# OR MERCHANTABILITY, EXCLUSIVITY, OR RESULTS OBTAINED FROM USE OF THE
# MATERIAL. CARNEGIE MELLON UNIVERSITY DOES NOT MAKE ANY WARRANTY OF ANY KIND
# WITH RESPECT TO FREEDOM FROM PATENT, TRADEMARK, OR COPYRIGHT INFRINGEMENT.
# 
# Licensed under a MIT-style license, please see license.txt or contact permission@sei.cmu.edu for full terms.
#
# [DISTRIBUTION STATEMENT A] This material has been approved for public
# release and unlimited distribution.  Please see Copyright notice for non-US
# Government use and distribution.
#
# This Software includes and/or makes use of Third-Party Software each
# subject to its own license.
#
# DM24-0786
# 
 
readonly _version="pubRel 240904a (branch: publicRelease)"

readonly _CONFSVR="${CONFSVR:=https://confluence.myhost.com:8095/confluence}"
#
# in bytes
# 0 means no limit
#
readonly _CONFSVRNOLIMIT=0
readonly _CONFSVRLIMIT="${CONFSVRLIMIT:=5242880}"

#
# simply utilities
#
_say()
{
  echo "${1}" "${2}" | ${__logger} >&"${_fdverbose}" && return
}

_warn()
{
  echo WARNING: "${*}" | ${__logger} >&"${_fdwarn}" && return
}

_debug()
{
  echo DEBUG: "${*}" | ${__logger} >&"${_fdwarn}" && return
}

_err()
{
  echo ERROR: "${*}" | ${__logger} >&"${_fderr}" && return
}

_fatal()
{
  [ -n "${*}" ] && echo FATAL: "${*}" | ${__logger} >&"${_fderr}"
  exit 1
}

_getyn()
{
  ! ${interactive} && return 0

  read -p "${1} (y=yes; n=no)? " -n 1 -r
  _say ""
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
      :
  else
    _say "aborting"
    return 1
  fi
  return 0
}

_find_Conf_pageByTitle()
{
  curl -k --silent --request GET \
    --header "authorization: Bearer ${CONF_PAT}" \
    --url "${_CONFSVR}/rest/api/search?cql=title=%22${1}%22+and+space=%22${2}%22" \
    | jq -r '.results[]|.content.id' | sed 's/^null$//g'

  return
}

_create_Conf_page()
{
  _say "trying to create ${2} in space ${1} under ${_ancestorTitle}"

  ! _getyn "continue" && echo "" && return 1

  local _temp
  local _title
  local _parentId

  _temp="$(mktemp)"
  _parentTitle="$(jq -j -r -n --arg fred "${_ancestorTitle}" '($fred|@uri)')"
  _parentId="$(_find_Conf_pageByTitle "${_parentTitle}" "${_spaceKey}")"

  if ! curl -k --silent \
    --header "Authorization: Bearer ${CONF_PAT}" \
    --request POST \
    --header 'Content-Type: application/json' \
    --data "{\"type\":\"page\",\"title\":\"${2}\", \"ancestors\":[{\"id\":${_parentId}}], \"space\":{\"key\":\"${1}\"},\"body\":{\"storage\":{\"value\": \"<p>This is a placeholder page created by curl</p>\",\"representation\":\"storage\"}}}" \
    --url "${_CONFSVR}/rest/api/content" -o "${_temp}"; then
    _warn "curl failed with ${?} see ${_temp}"
    echo ""
    return 1
  else
    [ -n "$(jq -j -r '.statusCode' < "${_temp}" | sed 's/null//g')" ] &&
      _warn "$(jq -j -r '.message' < "${_temp}" ) see ${_temp}" && return 2
  fi

  jq -j -r '.id' < "${_temp}"
  rm -f "${_temp}"

  return 0
}

_get_Conf_page()
{
  local _key
  local _title
  local _id

  _key="$(jq -j -r -n --arg fred "${1}" '($fred|@uri)')"
  _title="$(jq -j -r -n --arg fred "${2}" '($fred|@uri)')"

  _say "checking if ${2} exists..."
  #
  # TODO: make sure only 1 id is returned
  #       any more than 1 means the search
  #       was too broad
  #
  _id="$(_find_Conf_pageByTitle "${_title}" "${_spaceKey}")"

  _say "page id for ${2} in ${1} is ${_id}"

  [ -z "${_id}" ] && _id="$(_create_Conf_page "${1}" "${2}")"

  [ -z "${_id}" ] && _warn "unable to find or create page ${2} in ${1}" && return 4

  _say "getting title ${_title} from ${_key} to ${3}"

  #
  # strange, but seemingly bogus domain names
  # to af.mil fail but curl thinks all is good
  # really only need the version number as the 
  # content body (body.storage) will be
  # completely replaced in any event
  if ! curl -k --silent --request GET \
      --url "${_CONFSVR}/rest/api/content/${_id}?expand=version" \
      --header 'accept: application/json' \
      --header "authorization: Bearer ${CONF_PAT}" \
      -o "${3}" ; then
    _warn "curl failed with ${?}"
    return 1
  else
    [ -n "$(jq -j -r '.statusCode' < "${3}" | sed 's/null//g')" ] &&
      _warn "$(jq -j -r '.message' < "${3}")" && return 2
  fi

  _id="$(jq -j -r '.id' < "${3}" | sed 's/null//g')"
  [ -z "${_id}" ] && _warn "no page with title ${2} exists in space ${1}" && echo "" && return 3
	  
  echo "${_id}"

  return 0
}

_attach_to_Conf_page()
{
  _say "attaching ${2} to pageId ${1}"

  # strange, but seemingly bogus domain names
  # to af.mil fail but curl thinks all is good
  #
  # there are specific instruction on Atlassian
  # which all include 'X-Atlassian-Token: nocheck',
  # without that, this curl will fail
  # https://docs.atlassian.com/ConfluenceServer/rest/8.4.2/
  # TODO: may need 'allowDuplicated' parameter not sure
  #       as "reuploading" an existing file fails (design?)
  # TODO: good idea to see if the upload attachment by
  #       the same name is already there. large attachments
  #       will transfer first before being thrown back due
  #       to a name conflict (e.g., check_for_attachmane())
  if ! curl -k --silent -X POST \
      --header "X-Atlassian-Token: nocheck" \
      --header "Authorization: Bearer ${CONF_PAT}" \
      -F "file=@${2}" \
      -F 'minorEdit="true"' \
      -F "comment=body of evidence for oss-p4 report" \
      "${_CONFSVR}/rest/api/content/${1}/child/attachment" \
      -o "${2}.resp" ; then
    _warn "curl failed with ${?}"
    return 1
  else
    # just uploading one file so it is results[0]
    [ -z "$(jq -j -r '.results[0].id' "${2}.resp" 2>/dev/null | sed 's/null//g')" ] &&
      _warn "$(zcat "${2}.resp" | jq -r '.message')" && return 2
  fi

  return 0
}

_update_Conf_page()
{
  _say "updating content ${1} from ${2} in space ${_spaceKey} under ${_ancestorTitle}"

  ! _getyn "continue" && return 1

  # strange, but seemingly bogus domain names
  # to af.mil fail but curl thinks all is good
  if ! curl -k --silent -X PUT \
      --header "Authorization: Bearer ${CONF_PAT}" \
      --header 'Content-Type: application/json' \
      -d "@${2}" \
      "${_CONFSVR}/rest/api/content/${1}" -o "${2}.resp" ; then
    _warn "curl failed with ${?}"
    return 1
  else
    [[ (( $(stat -c %s "${2}") < $(stat -c %s "${2}.resp") )) ]] && _say "update: ok" && return 0

    [ -n "$(zcat "${2}.resp" | jq -j -r '.statusCode' | sed 's/null//g')" ] &&
      _warn "$(zcat "${2}.resp" | jq -j -r '.message')" && return 2
  fi

  return 0
}

_get_Page_version()
{
  local _v

  _say "getting version from ${1}"

  _v="$(jq -j -r '.version.number' < "${1}")"
  [ -n "${_v}" ] && echo "${_v}" && return 0

  echo ""
  return
}

#
# will error off if the expected resource and/or values
# need at runtime are not present or unknown for
# binary/commands, docker images, environment vars, and
# command line args
#
check_runtime()
{
  local _temp
  _rc=0 # 0 = no error, 1 = non recoverable error

  #
  # the binaries
  #
  for cmd in jq curl
  do
    [ -z "$(command -v ${cmd})" ] &&
      _err "required command, ${cmd}: not found in path or not installed" &&
      _rc=1
  done

  #
  # the env
  # TODO: allow a token to be passed on the CMD line (getopt)
  #       or pulled from secrets
  #
  # one var for this loop is okay for now
  # shellcheck disable=2043
  for eVar in CONF_PAT
  do
    if [[ -z "${!eVar}" ]]; then
      _err "required env variable, ${eVar}: not set"
      _rc=1
    fi
  done

  #
  # the command line
  #
  [ -z "${component}" ] &&
    _err "required local project name not specified (e.g., -C fleetth)" &&
    _rc=1

  { [ -z "${_ancestorTitle}" ] || [ -z "${_spaceKey}" ] || [ -z "${_pageTitle}" ]; } &&
    _fatal "-A, -S, & -T all must be set"

  #
  # attachment(s)
  # TODO: support more than one file (e.g., file1,file2,file3)
  #
  [[ -n "${attachment}" ]] && [ ! -f "${component}/${attachment}" ] && [ ! -f "${attachment}" ] &&
    _fatal "specified attachment, (-a ${attachment}) not found"

  #
  # lastly, check the Confluence PAT and spaceKey for goodness
  #
  _temp="$(mktemp)"
  _hc=$(curl  -w "%{http_code}" -k --silent --request GET \
    --header "authorization: Bearer ${CONF_PAT}" \
    --header 'Accept: application/json, text/javascript, */*; q=0.01' \
    --url "${_CONFSVR}/rest/spacedirectory/1/search?query=spacekey%3A${_spaceKey}&type=global&status=current" \
    --output "${_temp}")

  case ${_hc} in
    401) _rc=1 && _err CONF_PAT: appears to be no good, refresh your Confluence PAT
         ;;
    200) [ "$(jq -r '.spaces[0].key' "${_temp}")" = "null" ] && _rc=1 && _err "bad spacekey: ${_spaceKey}"
         ;;
    *) _say "confirmed ${_spaceKey} is available using your Confluence PAT"
         ;;
  esac

  rm -f "${_temp}"
  return ${_rc}
}

#
# main
#{

preserve="false"
quiet="false"
verbose="false"
interactive="false"

component=
attachment=
attachonly=false

#
# errors always go to stderr
#
_fderr=2
_fdwarn=2

#
# never send to stdout
#
_fdverbose=/dev/null

_spaceKey="MYDOCS"
_pageTitle=""
_ancestorTitle="Example OSS Reports"
__logger="cat"
__logfil=""

_cmdline="${0} ${*}"

while getopts "a:hilopqvA:C:S:T:V" opt; do #{
  case $opt in
    a) attachment="${OPTARG}"
       [[ -s "${attachment}" ]] && attachment=$(realpath "${attachment}")
       [[ ! -s "${attachment}" ]] && _fatal "cannot resolve ${OPTARG} as ${attachment}"
       ;;
    i) interactive="true" ;;
    l) __logfil="pub-$(date +%Y%m%d-%H%M%S).log" ;;
    o) attachonly="true" ;;
    p) preserve="true" ;;
    q) quiet="true" ;;
    v) verbose="true" ;;
    A) _ancestorTitle="${OPTARG}" ;;
    C) component="${OPTARG}" ;;
    S) _spaceKey="${OPTARG}" ;;
    T) _pageTitle="${OPTARG}" ;;
    V) echo "Version: ${_version} for Server at ${_CONFSVR}" && _fatal "" ;;
    h|*) cat <<-_OPTSEOF
  USAGE: ${0} [OPTIONS]

  OPTIONS

  -a:  file to attach to the page (e.g., body of evidence)
  -h:  this message (and exit)
  -l:  log output messages to file of the form 'pub-YYYYMMDD-HHMMSS.log' in 'logs' folder
  -o:  attach file only without changing page itself
  -p:  preserve local working files and responses (for testing)
  -q:  quiet (overrides verbose, warnings)
  -v:  verbose, not quiet
  -A:  Ancestor page title (default: 'OSS Intel Requests')
  -C:  set local component name/project name (REQUIRED)
  -S:  Space in Confluence (default: MYDOCS)
  -T:  Page Title (default: same as -C with ' auto' appended)
  -V:  display version (and exit)

_OPTSEOF
       _fatal ""
  esac
done #}
shift $((OPTIND-1))

${verbose} && [ "${quiet}" = "false" ] &&
  _fdverbose="${_fdwarn}" && _say "setting verbose to fd:${_fdverbose}"

#
# quiet overrides any warning/verbose options
#
${quiet} &&
  _fdwarn=/dev/null &&
  _fdverbose=/dev/null

#
# properly set up logfile if necessary
#
[[ -n "${__logfil}" ]] && __logger="tee -a ${__logfil}" && cp /dev/null "${__logfil}" && _rp="$(realpath -e "${__logfil}")"

_say "cmdline: ${_cmdline}"

[ -z "${_pageTitle}" ] && _pageTitle="${component} auto"

#
# check runtime requirements
#
if ! check_runtime; then _fatal "exiting due to missing runtime requirement(s)"; fi

_say "setting current working folder to ${component}"
cd "${component}" || _fatal "can't set working folder to ${component}"

#
# since 'preMVP 240507a (branch: main)' tidy
# up all logfiles to a logs folder, work
# legacy pub runs to this same folder
#
mkdir -p logs/
[[ -d logs ]] && find  . -maxdepth 1 -name pub-\*.log -print0 | xargs -0 -I {} mv {} ./logs/

#
# this log file will be moved later before exit/cd ..
#
[[ -n "${__logfil}" ]] && mv -f "${_rp}" "."

_outfileCache=${component}-vUNK.json

if ! _pageId="$(_get_Conf_page "${_spaceKey}" "${_pageTitle}" "${_outfileCache}")"; then
  _fatal "page not found"
fi
_say "got pageId=${_pageId} with rc=${?}"

${attachonly} && [[ -n "${attachment}" ]] && {
    _say "Only uploading attachment ${attachment}";
    if ! _attach_to_Conf_page "${_pageId}" "${attachment}"; then
      _fatal "attachment failed"
    fi;
    _say "done.";
    [[ -n "${__logfil}" ]] && mv -f "${__logfil}" "./logs/"
    cd ..;
    exit 0;
  }

_oldVersion="$(_get_Page_version "${_outfileCache}")"
_say "got oldVersion=${_oldVersion}"
_newVersion="$((_oldVersion+1))"
_say "now newVersion=${_newVersion}"

_bodyValue="${component}_scir.html"
_vumaValue="${component}_vulmalrep.html"

_say "body is ${_bodyValue}"
_say "vuls and mal is ${_vumaValue}"

[ ! -s "${_vumaValue}" ] && _warn "no ${_vumaValue} file, using placeholder" && cp /dev/null "${_vumaValue}"
#
# test for resource limit(s)
#  if too big, drop the vuls and mal report and treat as if "not there" like above
#  so the TOO BIG report can be attached to the report
#
[[ ${_CONFSVRLIMIT} -gt ${_CONFSVRNOLIMIT} ]] && \
  if [[ $(( $(stat --printf="%s" "${_bodyValue}") + $(stat --printf="%s" "${_vumaValue}") )) -gt ${_CONFSVRLIMIT} ]]; then
    _warn "${_vumaValue} file is too large for ${_CONFSVR} being greater than ${_CONFSVRLIMIT} bytes, please attach using: '${0}' -l -v -C '${component}' -T '${_pageTitle}' -S '${_spaceKey}' -A '${_ancestorTitle}' -o -a '${_vumaValue}'"
    _vumaValue="$(mktemp)"
    cp /dev/null "${_vumaValue}"
  fi

#
# TODO: control chars in the body, vuls, and mal
#       files includes in this json struct will
#       fail to upload properly. the tr(1) -d
#       will wack carriage returns, newline and tabs,
#       but extreme cases may require more aggressive
#       treatment (for example tr -dc '[:print:]' which
#       will only keep printable chars (and all
#       remove control chars)
#
json_data=$(
cat <<-_JSONEOF
{
  "type": "page",
  "title": "${_pageTitle}",
  "version": {
    "number": ${_newVersion}
  },
  "body": {
    "storage": {
      "value": "<blockquote><h6><span style='color: rgb(51,102,255);'>WARNING: Do not hand edit, this page is subject to automatic updates.</span></h6></blockquote><p><ac:structured-macro ac:macro-id='f707e5aa-a879-42ee-b21c-bb6baad398fc' ac:name='toc' ac:schema-version='1'><ac:parameter ac:name='maxLevel'>3</ac:parameter></ac:structured-macro></p>$(tr -d '\r\n\t' < "${_bodyValue}")<p/>$(tr -d '\r\n\t' < "${_vumaValue}")<blockquote><sup>Created by pub-scir ${_version} on $(date)</sup></blockquote>",
      "representation": "storage"
    }
  }
}
_JSONEOF
)

#
# TODO: make report using confluence template
#       from data collected in summary
#       output file
#
echo "${json_data}" > "${component}_scir-v${_newVersion}-update.json"

_say "checking json syntax for ${component}_scir-v${_newVersion}-update.json"
! jq -r '.' "${component}_scir-v${_newVersion}-update.json" >/dev/null && _fatal "file not in proper JSON format, cannot continue"

if ! _update_Conf_page "${_pageId}" "${component}_scir-v${_newVersion}-update.json"; then
  _fatal "update failed"
fi

#
# conditionally clear working files
#
! ${preserve} && 
  _say "removing local working files" &&
  rm "${_outfileCache}" \
    "${component}_scir-v${_newVersion}-update.json" \
    "${component}_scir-v${_newVersion}-update.json.resp"

[[ -n "${attachment}" ]] &&
  if ! _attach_to_Conf_page "${_pageId}" "${attachment}"; then
    _fatal "attachment failed"
  fi

_say "done."

[[ -n "${__logfil}" ]] && mv -f "${__logfil}" "./logs/"
cd ..

exit 0
#}
