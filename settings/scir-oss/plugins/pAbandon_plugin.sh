#
# convention use _p_ to shield/protect global vars from main or other plugins
# must be unique from other check names
#

declare -g _p_PABANDON_checkname="ProjectAbandoned"
declare -g _p_PABANDONDep_checkname="DepProjectsAbandoned"
declare -g _p_PABANDONTer_checkname="TertiaryProjectsAbandoned"

declare -g -a _p_PABANDONhits

#
# lifecycle main -> involkes init -> -> cache -> run -> report in that order
#
# init: used to structurally integrate plugin check with other check structures
# cache: any caching that may need to occur before run
# run: perform check
# report: report results
#
_p_pAbandon_init()
{
  # P4
  # required (defines where scores are consolidated):
  # register check name under MYscore checks, pick one of four
  #   - PFourProjectChecks
  #   - PFourProductChecks
  #   - PFourProtectionChecks
  #   - PFourPolicyChecks
  #
  PFourProjectChecks[MYscore]+=" ${_p_PABANDON_checkname}"
  PFourProjectChecks[MYscore]+=" ${_p_PABANDONDep_checkname}"
  PFourProjectChecks[MYscore]+=" ${_p_PABANDONTer_checkname}"

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
  CIOlongTermChecks[MYscore]+=" ${_p_PABANDON_checkname}"
  CIOlongTermChecks[MYscore]+=" ${_p_PABANDONDep_checkname}"
  CIOlongTermChecks[MYscore]+=" ${_p_PABANDONTer_checkname}"

  # which section of the report results are shown
  # will align with the CIO check above
  #
  # pick one of six
  #   _LOCAL_SECTION___SECURITY_ID
  #   _LOCAL_SECTION___INTEGRITY_ID
  #   _LOCAL_SECTION___DEPENDENCIES_ID
  #   _LOCAL_SECTION___MALICIOUS_ACTORS_ID
  #   _LOCAL_SECTION___LONG_TERM_SUPPORT_ID
  #   _LOCAL_SECTION___SUITABILITY_ID
  #
  pAbandon_section="${_LOCAL_SECTION___LONG_TERM_SUPPORT_ID}"

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
  pAbandon_position="${__REPORT__SECTION__TAIL__}"

  #
  # label at it will appear in the CIO summary table
  #
  MYcheckLabels[${_p_PABANDON_checkname}]="Project Abandoned"
  MYcheckLabels[${_p_PABANDONDep_checkname}]="Dependent Projects Abandoned"
  MYcheckLabels[${_p_PABANDONTer_checkname}]="Subdependent Projects Abandoned"

  MYcheckScores[${_p_PABANDON_checkname}]="false"
  MYcheckScores[${_p_PABANDONDep_checkname}]="0"
  MYcheckScores[${_p_PABANDONTer_checkname}]="0"

  MYcheckWeights[${_p_PABANDON_checkname}]="${SCcritical}"
  MYcheckWeights[${_p_PABANDONDep_checkname}]="${SChigh}"
  MYcheckWeights[${_p_PABANDONTer_checkname}]="${SClow}"

  MYcheckThresholds[${_p_PABANDON_checkname}]="false"
  MYcheckThresholds[${_p_PABANDONDep_checkname}]="0"
  MYcheckThresholds[${_p_PABANDONTer_checkname}]="0"

  #
  # 0 success
  # otherwise failure and plugin will not be run or report
  #
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
_p_pAbandon_run()
{
  local _repo
  local _committer
  local _ghapijson
  local _i
  local _c

  _ghapijson="${2}_ghapi.json"

  _say -n "Counting abandoned projects..."

  MYcheckScores["${_p_PABANDON_checkname}"]="$(jq -r '.archived' "${_ghapijson}")"

  #
  # scorecard 5.0 changed the "reason" check for both
  # also find w/ grep -v ensure didn't count main project
  #
  MYcheckScores["${_p_PABANDONDep_checkname}"]="${__NAN__}"
  _i=0
  _c=0
  while IFS= read _sc
  do
    grep --quiet -E '(repo is marked as archived|project is archived)' "${_sc}" && ((_i++));
    ((_c++))
  done < <(find ./deps.d -name \*sc.json|grep -v "___${2}/")
  #
  # if looped at least once, a search was conducted
  # and count (_i) is meaningful; otherwise no pri
  # dependencies were searched
  #
  [[ ${_c} -gt 0 ]] && MYcheckScores["${_p_PABANDONDep_checkname}"]="${_i}"

  #
  # are any of the tertiary dependencies abandoned (med)
  #_tarchived="$(find ./subdeps.d/ -name \*sc.json -print0 | \
  #  xargs -0 grep "repo is marked as archived" | cut -d: -f1|wc -l)"
  #
  MYcheckScores["${_p_PABANDONTer_checkname}"]="${__NAN__}"
  _i=0
  _c=0
  [[ -d "./subdeps.d/" ]] &&
    while IFS= read _sc
    do
      grep --quiet -E '(repo is marked as archived|project is archived)' "${_sc}" && ((_i++));
      ((_c++))
    done < <(find ./subdeps.d/ -name \*sc.json)
  [[ ${_c} -gt 0 ]] && MYcheckScores["${_p_PABANDONTer_checkname}"]="${_i}"

  _say "done."
  return 0
}

#
# use echo(1) to return/show values to report
#
_p_pAbandon_report()
{
  local _ptxt
  local _dtxt
  local _ttxt

  _ptxt="is not"
  [[ "${MYcheckScores["${_p_PABANDON_checkname}"]}" == "true" ]] && _ptxt="is"

  _ptxt="${component} $(_fotp "${MYcheckScores["${_p_PABANDON_checkname}"]}" "${MYcheckThresholds["${_p_PABANDON_checkname}"]}")${_ptxt} archived; "

  _dtxt="$(_fotp "${__NAN__}")primary dependencies were not checked. (see -D); "
  [[ ! "${MYcheckScores["${_p_PABANDONDep_checkname}"]}" = "${__NAN__}" ]] && _dtxt="$(_fotp "${MYcheckScores["${_p_PABANDONDep_checkname}"]}" "${MYcheckThresholds["${_p_PABANDONDep_checkname}"]}" "gt")${MYcheckScores["${_p_PABANDONDep_checkname}"]} of the primary dependencies are abandoned; "

  _ttxt="$(_fotp "${__NAN__}")tertiary (other) dependencies were not checked. (see -D)"
  [[ ! "${MYcheckScores["${_p_PABANDONTer_checkname}"]}" = "${__NAN__}" ]] && _ttxt="$(_fotp "${MYcheckScores["${_p_PABANDONTer_checkname}"]}" "${MYcheckThresholds["${_p_PABANDONTer_checkname}"]}" "gt")${MYcheckScores["${_p_PABANDONTer_checkname}"]} of the tertiary subdependencies are abandoned"

  echo "${_ptxt}${_dtxt}${_ttxt}"

  return 0
}

#
# plugin interface
#

#
# only loads if specifically set to true (no quotes)
# must match pattern '^[[:space:]]*crink_enabled=true[[:space:]]*$'
#
pAbandon_enabled=true

## associative array of detailed results
pAbandon_results="_p_PABANDONhits"

## need to have values for report results
pAbandon_name="Abandoned Projects check"
#
# no spaces
pAbandon_id="Abandoned_Projects"
pAbandon_label="Number of Abandoned Project(s)"
pAbandon_desc="Projects identified, explicitly by way of OSSF Scorecard and/or GitHub's API as being marked as archived"
pAbandon_risk=""

## plugin lifecycle callbacks
#
# although there are three checks
# these three are all handled by the
# one callback for init, cache, run, report
#
pAbandon_init="_p_pAbandon_init"
pAbandon_run="_p_pAbandon_run"
pAbandon_report="_p_pAbandon_report"
