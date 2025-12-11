#
# convention use _p_ to shield/protect global vars from main or other plugins
# must be unique from other check names
#

declare -g _p_AFFIL_checkname="AffiliatedAuthor"

declare -g -A _p_AFFILhits=()

_p_affil_total_contribs=0
#
# TODO: dynamically determine VCS/repo based on
#       dependency with hipcheck and detect_sdn()
#       in the main scir-oss.sh script
#
_p_affil_known_repohost="github.com"

#
# lifecycle main -> involkes init -> -> cache -> run -> report in that order
#
# init: used to structurally integrate plugin check with other check structures
# cache: any caching that may need to occur before run
# run: perform check
# report: report results
#
_p_affil_init()
{
  _p_affil_setupHelpers
  # P4
  # required (defines where scores are consolidated):
  # register check name under MYscore checks, pick one of four
  #   - PFourProjectChecks
  #   - PFourProductChecks
  #   - PFourProtectionChecks
  #   - PFourPolicyChecks
  #
  PFourPolicyChecks[MYscore]+=" ${_p_AFFIL_checkname}"

  # CIO
  # required (defines where scores are consolidated):
  # register check name under MYscore checks, pick one of six
  #   - CIOlongTermChecks
  #   - CIOdependencyChecks
  #   - CIOsecurityChecks
  #   - CIOintegrityChecks
  #   - CIOmalActorsChecks
  #   - CIOsuitabilityChecks
  #
  CIOsuitabilityChecks[MYscore]+=" ${_p_AFFIL_checkname}"

  # which section of the report results are shown
  # will align with the CIO check above
  #
  # pick on one of six
  #   _LOCAL_SECTION___SECURITY_ID
  #   _LOCAL_SECTION___INTEGRITY_ID
  #   _LOCAL_SECTION___DEPENDENCIES_ID
  #   _LOCAL_SECTION___MALICIOUS_ACTORS_ID
  #   _LOCAL_SECTION___LONG_TERM_SUPPORT_ID
  #   _LOCAL_SECTION___SUITABILITY_ID
  #
  affil_section="${_LOCAL_SECTION___SUITABILITY_ID}"

  #
  # pick one as to where within the section results
  # the report should appear
  #
  #  among those in the beginning
  #  __REPORT__SECTION__HEAD__
  #  anywhere in the section
  #  __REPORT__SECTION__HERE__
  #  among those at the end
  #  __REPORT__SECTION__TAIL__
  #
  affil_position="${__REPORT__SECTION__TAIL__}"

  #
  # label at it will appear in the CIO summary table
  #
  MYcheckLabels[${_p_AFFIL_checkname}]="Affiliated Author"

  MYcheckScores[${_p_AFFIL_checkname}]="0"

  # these defaults, may be set in _p_affil_setupHelpers
  # via config file, set otherwise
  [[ ! -v MYcheckWeights[${_p_AFFIL_checkname}] ]] && {
    MYcheckWeights[${_p_AFFIL_checkname}]="${SClow}"

    MYcheckThresholds[${_p_AFFIL_checkname}]="0"

    #
    # check if should be advisatory (rather than error/redFlag)
    #
    _p_affil_advisoryClass=
    _p_affil_advisoryFlag=
    [[ ${MYcheckWeights[${_p_AFFIL_checkname}]} == "${SClow}" ]] || [[ ${MYcheckWeights[${_p_AFFIL_checkname}]} == "${SCmedium}" ]] && {
      _p_affil_advisoryClass=":warn"
      _p_affil_advisoryFlag='--warnFlag'
    }
    advisoryChecks[${_p_AFFIL_checkname}${_p_affil_advisoryClass}]+="gt"
  }

  #
  # 0 success
  # otherwise failure and plugin will not be run or report
  #
  return 0
}

#
# this plugin relies on MITRE's hipcheck v3.14 or greater
# for the affiliation analysis. This helper ensure that
# version of hipcheck is installed and configured for that
# analysis
#
# the parameters for the helper are in the plugin settings
# folder under the scir_oss settings
#

_p_affil_affiliationHelper=""
_p_affil_affiliationPolicy=""

_p_affil_setupHelpers()
{
  local _config

  _config="${_OSSSCIRsettings}/scir-oss/plugins/affil_plugin/config.json"

  #
  # ensure the plugin settings are available
  #
  ! [[ -f "${_config}" ]] &&
      _warn "${_p_AFFIL_checkname}: cannot find $(basename "${_config}") under ${_OSSSCIRsettings}/scir-oss/plugins/affil_plugin/" && return 1

  #
  # ensure the affiliationChecker program is in available
  #
  _p_affil_affiliationHelper="$(jq -r '.affiliationChecker.program.exec.name' "${_config}")"
  [[ ! "default" == "$(jq -r '.affiliationChecker.program.exec.path' "${_config}")" ]] &&
    _p_affil_affiliationHelper="$(jq -r '.affiliationChecker.program.exec.path' "${_config}")"/"$(jq -r '.affiliationChecker.program.exec.name' "${_config}")"
  [[ -z "$(command -v "${_p_affil_affiliationHelper}")" ]] &&
    _warn "${_p_AFFIL_checkname}: cannot find ${_p_affil_affiliationHelper}" && return 1

  #
  # ensure the affiliationChecker config is in available
  #
  _p_affil_affiliationPolicy="${_OSSSCIRsettings}/$(jq -r '.affiliationChecker.program.config.folder' "${_config}")/config/Hipcheck.kdl"
  [[ ! "default" == "$(jq -r '.affiliationChecker.program.config.path' "${_config}")" ]] &&
    _p_affil_affiliationPolicy="$(jq -r '.affiliationChecker.program.config.path' "${_config}")"/"$(jq -r '.affiliationChecker.program.config.folder' "${_config}")"/config/Hipcheck.kdl
  [[ ! -f "${_p_affil_affiliationPolicy}" ]] &&
    _warn "${_p_AFFIL_checkname}: cannot find ${_p_affil_affiliationPolicy}" && return 1

  case "$(jq -r '.affiliationChecker.p4report.scoreWeight|select (.!=null)' "${_config}")" in
    critical) MYcheckWeights[${_p_AFFIL_checkname}]="${SCcritical}" ;;
    high) MYcheckWeights[${_p_AFFIL_checkname}]="${SChigh}" ;;
    medium) MYcheckWeights[${_p_AFFIL_checkname}]="${SCmedium}" ;;
    low) MYcheckWeights[${_p_AFFIL_checkname}]="${SClow}" ;;
    none) MYcheckWeights[${_p_AFFIL_checkname}]="${SCnone}" ;;
    *)
      # do nothing, keep defaults
      ;;
  esac

  MYcheckThresholds[${_p_AFFIL_checkname}]="$(jq -r '.affiliationChecker.program.policy.threshold' "${_config}")"

  #
  # check if should be advisatory (rather than default error/redFlag)
  #
  unset "advisoryChecks[${_p_AFFIL_checkname}${_p_affil_advisoryClass}]"
  _p_affil_advisoryClass=
  _p_affil_advisoryFlag=
  case "$(jq -r '.affiliationChecker.p4report.alertLevel|select (.!=null)' "${_config}")" in
    info)    _p_affil_advisoryFlag='--infoFlag'
             _p_affil_advisoryClass=":info"
             ;;
    warning) _p_affil_advisoryFlag='--warnFlag'
             _p_affil_advisoryClass=":warn"
             ;;
    *)
      # do nothing, keep defaults
      ;;
  esac
  advisoryChecks[${_p_AFFIL_checkname}${_p_affil_advisoryClass}]+="gt"

  #
  # ensure that the affiliation helper is ready to run
  #
  ! "${_p_affil_affiliationHelper}" --verbosity quiet --policy "${_p_affil_affiliationPolicy}" ready 2>/dev/null 1>&2 &&
    _warn "${_p_AFFIL_checkname}: ${_p_affil_affiliationHelper} failed setup check(s)" && return 1

  return 0
}
#
#
# args are:
#  1: "${component}" passed by -C as in 'oparest'
#     this is the prefix for files generally created by OSS-P4/R
#  2: "$(basename "${gh_site}")" basename as in 'opa-restful' as passed by -G as in 'go-training/opa-restful'
#     this is the prefix for cache files from github API and git CLI
#  3: (future reserved)
#  4: (future reserved)
#
_p_affil_run()
{
  local _repo
  local _committer
  local _contribs
  local _hcache
  local _cwd

  #
  # dependant file _contribs generated by the detect_sdn() capability of scir-oss.sh
  # TODO: devise and add plugin dependency scheme/ordering
  #
  _say -n "Counting Affiliated Authors..."

  affil_detailreport="${1}_${_p_AFFIL_checkname}.csv"
  _contribs="${2}_gitcli_contrib.csv"

  _cwd="$(realpath "${PWD}")"
  #
  # TODO: make a plugin support tool to get this
  #       from the sourcing environment
  #       (e.g., _plugin_getHipcheckCache)
  #
  _hcache="${_MITRHCcache}"
  ${_useDocker} && _hcache="${HOME}/.cache/hipcheck"

  echo "\"tld\",\"Contributor Email\",\"Project Contributed\"" > "${affil_detailreport}"

  while IFS= read -r _x
  do
    local _affDir
    _affDir="$(basename "$(dirname "${_x}")"|sed 's/___/\//g')";
    { pushd "${_hcache}/clones/github/${_affDir}" >/dev/null 2>&1; } || { _warn "cannot identify committers to ${_affDir}" && continue; }

  #
  # run affiliation helper against all repos (primary and dependency repos)
  #
    { while IFS= read -r _committer
    do
      _p_AFFILhits["${_affDir},${_committer}"]="{ \"committer\":\"${_committer}\", \"repo\": \"${_affDir}\" }"
      echo "\"${_committer##*.}\",\"${_committer}\",\"${_p_affil_known_repohost}/${_affDir}\""
    done < <(
              "${_p_affil_affiliationHelper}" \
                --verbosity quiet \
                --config "$(dirname "${_p_affil_affiliationPolicy}")" \
                --policy "${_p_affil_affiliationPolicy}" \
                --format json check -t repo "https://${_p_affil_known_repohost}/${_affDir}" \
              | \
              jq -r '.|select (.failing[0].final_value > 0)|.failing[0].concerns[]' \
              | \
              sed -n 's/.*(\([^)]*\)).*/\1/p' | \
              sort | \
              uniq \
             ); } >> "${_cwd}/${affil_detailreport}"

    popd > /dev/null || cd "${_cwd}" || break
  done < <(find . ! -size 0 -type f -iname \*hc.json);

  MYcheckScores[${_p_AFFIL_checkname}]="${#_p_AFFILhits[@]}"
  _p_affil_total_contribs="$(sort < "${_contribs}" | uniq | wc -l)"

  _say "done."
  return 0
}

#
# use echo(1) to return/show values to report
#
_p_affil_report()
{
  local _msg
  local _t

  _msg=", no Affiliated author(s) detected."
  _t=$(grep -c -v "Contributor Email" <"${affil_detailreport}")
   [[ ${_t} \
     -gt \
     ${MYcheckThresholds[${_p_AFFIL_checkname}]} ]] && {
     _msg=", detected author(s) from tld(s) "
     while IFS= read -r _c;
     do
       # shellcheck disable=SC2116
       _msg="${_msg}$(echo "${_c}=$(grep -c -E "^\"${_c}" "${affil_detailreport}"), ")"
     done < <(grep -v "Contributor Email" <"${affil_detailreport}"|csvtool col 1 -|sort|uniq)
     _msg="${_msg/%, /} which comprise $(printf "%.3f%% of all %'.0f contributors" "$(bc -l <<<"${_t}/${_p_affil_total_contribs}*100")" "${_p_affil_total_contribs}")"
   }

  echo "$(\
    # shellcheck disable=SC2086
    _fotp ${_p_affil_advisoryFlag} \
      "${MYcheckScores[${_p_AFFIL_checkname}]}" \
      "${MYcheckThresholds[${_p_AFFIL_checkname}]}" \
      "gt" \
    )${MYcheckScores[${_p_AFFIL_checkname}]}/${MYcheckThresholds[${_p_AFFIL_checkname}]}${_msg}"

  return 0
}

#
# plugin interface
#

#
# only loads if specifically set to true (no quotes)
# must match pattern '^[[:space:]]*affil_enabled=true[[:space:]]*$'
#
affil_enabled=false

## associative array of detailed results
affil_results="_p_AFFILhits"
## if any detailed results in a file
## name is set here in _run fn
affil_detailreport=""

## need to have values for report results
affil_name="Affiliated Authors check"
affil_id="AFFIL_Author"
affil_label="Affiliated Author(s)"
affil_desc="Contributors with email identifing with domains of interest"
affil_risk=""

## plugin lifecycle callbacks
affil_init="_p_affil_init"
affil_run="_p_affil_run"
affil_report="_p_affil_report"
