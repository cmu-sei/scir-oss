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
 
#
# to find main search down for __main__
# bash entrypoint (bash script start) search down for __entrypoint__
# bash exitpoint search down for _cleanup_and_exit (often rearchable from _fatal
#

readonly _version="pubRel 240904a (branch: publicRelease)"
readonly _OSSFSC="${_OSSFSC:=gcr.io/openssf/scorecard:latest}"
readonly _OSSFCS="${_OSSFCS:=${HOME}/go/bin/criticality_score}"
readonly _MITRHC="${_MITRHC:=hipcheck:2022-07-06-delivery}"
#
# check_runtime will confirm these settings
# if the path does not exist, it will be updated
# to realpath for arg 0, if that fails _fatal error will
# be raised
#
# TODO: make this 'settings' folder path/name a command line arg
#
_OSSSCIRsettings="/vagrant/scir-oss/settings"
_MITRHCconfig="${_OSSSCIRsettings}/hipcheck/config"
_MITRHCscripts="${_OSSSCIRsettings}/hipcheck/scripts"
_OSSSCIRlicenseDB="${_OSSSCIRsettings}/mychecks/licenseDB.json"

#readonly _MITRHC="hipcheck:2022-07-06-delivery"

#
# simply utilities
#

#
# make sure to handle / process logfile
#
_cleanup_and_exit()
{
  _say "oss-p4/4 done."
  [[   "${__logfil}" == "${__NULLLOG__}" ]] && rm -f "${__logfil}"
  [[ ! "${__logfil}" == "${__NULLLOG__}" ]] && [[ -f "${__logfil}" ]] && mv "${__logfil}" logs/

  #
  # shellcheck disable=2164
  ! dirs -v |tail -1 | grep -q '^ 0' && popd
  exit "${1}"
}

_say()
{
  echo "${1}" "${2}" | ${__logger} >&"${_fdverbose}" && return
}

_info()
{
  _HTMLcaveats+=("I: ${*}<br/>")
  echo INFO: "${*}" | ${__logger} >&"${_fdwarn}" && return
}

_warn()
{
  _HTMLcaveats+=("W: ${*}<br/>")
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
  _cleanup_and_exit 1
}

#
# using package names from phylum results in 
# bad string chars for unix files, ensure there
# are no strange chars in the filename
#
mkdepdir()
{
  #[ -z "$(command -v inline-detox)" ] && echo "${_c////___}" && return 0
  #echo "${_c////===}" | inline-detox
  #
  # TODO: make this twoway (perhaps url encoding (e.g., %2F)
  #       _folder="$(jq -j -r -n --arg fred "${1}" '($fred|@uri)')"
  #
  # for now '/' become '___' and all those chars
  # in the '[]' below become '_'
  echo "${1}" | sed 's^/^___^g;s/[*^~<>#@]/_/g'
  return 0
}

#
# OSS-P4/R report writer helpers
#

#
# confluence-specific HTML
#
readonly __REDFLAG__="<ac:emoticon ac:name='cross'/>"
readonly __WARNING__="<ac:emoticon ac:name='warning'/>"
readonly __SECTION__="<hr style='border: 10px solid gray; border-radius: 5px'/>"

readonly __NULLGH__=":owner/:repo"
readonly __NULLPURI__=":eco:name:ver"
__NULLLOG__="$(mktemp -u -p .)"
readonly __NULLLOG__
readonly __TIMEOUT__="300"

#readonly _fpdigitsRE='^[+-]?[0-9]+([.][0-9]+)?$'
readonly _fpdigitsRE='^[+-]?[0-9]*([.][0-9]+)?$'

readonly __NAN__="NaN"
readonly __CHECKNOTIMPL__="NoImp"
readonly __NOCHECK__="NoCheck"
readonly _SCthreshold="3.3"
readonly _CSthreshold="0.2"
readonly _HCthreshold="0.50"
readonly _PHthreshold="0.60"
readonly __CONTRIBCNT__="3"
readonly __ACTIVEDAYS__="$(( 71 * 7 ))"
readonly __DAYSNEW__="$(( 35 * 7 ))"

readonly SCcritical="10.0"
readonly SChigh="7.5"
readonly SCmedium="5.0"
readonly SClow="2.5"
readonly SCfail="-1"

_HTMLcaveats=()

_HTMLfootnotes=()

#
# P4 outlook tables
#
declare -A PFourProjectChecks=( \
  [SCscore]="Code-Review CI-Tests CII-Best-Practices Contributors Fuzzing Maintained SAST" \
  [HCscore]="Activity Identity Affiliation Fuzz Review" \
  [PHYscore]="author" \
  [MYscore]="ProjectForked ProblemReporting DepProjectsForked TertiaryProjectsForked ProjectAbandoned DepProjectsAbandoned TertiaryProjectsAbandoned" \
  )

declare -A PFourProjectScores=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A PFourProjectScoresWeights=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A PFourProductChecks=( \
  [SCscore]="Packaging Binary-Artifacts Vulnerabilities" \
  [HCscore]="Binary Churn Entropy Typo" \
  [PHYscore]="engineering malicious_code vulnerability" \
  [MYscore]="UnfixedVulnerabilities" \
  )

declare -A PFourProductScores=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A PFourProductScoresWeights=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${SChigh}" \
  [HCscore]="${SChigh}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A PFourProtectionChecks=( \
  [SCscore]="Branch-Protection Dangerous-Workflow Dependency-Update-Tool Signed-Releases Token-Permissions Webhooks" \
  [HCscore]="${__NOCHECK__}" \
  [PHYscore]="${__NOCHECK__}" \
  [MYscore]="${__NOCHECK__}" \
  )

declare -A PFourProtectionScores=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A PFourProtectionScoresWeights=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SClow}" \
  [PHYscore]="${SClow}" \
  [MYscore]="${SCcritical}" \
  )

declare -A PFourPolicyChecks=( \
  [SCscore]="License Security-Policy" \
  [HCscore]="${__NOCHECK__}" \
  [PHYscore]="license" \
  [MYscore]="ProjectRestrictiveLicense DepProjectsRestrictiveLicense TertiaryProjectsRestrictiveLicense" \
  )

declare -A PFourPolicyScores=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A PFourPolicyScoresWeights=( \
  [P4score]="${__NAN__}" \
  [SCscore]="${SChigh}" \
  [HCscore]="${SClow}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

#
# CIO criteria tables
#
declare -A CIOlongTermChecks=( \
  [SCscore]="Contributors Maintained CII-Best-Practices Security-Policy" \
  [HCscore]="Activity" \
  [PHYscore]="${__NOCHECK__}" \
  [MYscore]="ProjectForked ProblemReporting DepProjectsForked TertiaryProjectsForked ProjectAbandoned DepProjectsAbandoned TertiaryProjectsAbandoned" \
  )

declare -A CIOlongTermScores=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A CIOlongTermWeights=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A CIOdependencyChecks=( \
  [SCscore]="Dependency-Update-Tool Pinned-Dependencies" \
  [HCscore]="${__NOCHECK__}" \
  [PHYscore]="${__NOCHECK__}" \
  [MYscore]="${__NOCHECK__}" \
  )

declare -A CIOdependencyScores=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A CIOdependencyWeights=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A CIOsecurityChecks=( \
  [SCscore]="Binary-Artifacts Branch-Protection Dangerous-Workflow Token-Permissions Vulnerabilities Webhooks" \
  [HCscore]="Binary Churn Entropy Typo" \
  [PHYscore]="engineering malicious_code vulnerability" \
  [MYscore]="UnfixedVulnerabilities" \
  )

declare -A CIOsecurityScores=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A CIOsecurityWeights=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A CIOintegrityChecks=( \
  [SCscore]="Code-Review CI-Tests Fuzzing SAST Packaging Signed-Releases" \
  [HCscore]="Identity Fuzz Review" \
  [PHYscore]="${__NOCHECK__}" \
  [MYscore]="${__NOCHECK__}" \
  )

declare -A CIOintegrityScores=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A CIOintegrityWeights=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A CIOmalActorsChecks=( \
  [SCscore]="${__NOCHECK__}" \
  [HCscore]="Affiliation" \
  [PHYscore]="author" \
  [MYscore]="${__NOCHECK__}" \
  )

declare -A CIOmalActorsScores=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A CIOmalActorsWeights=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

declare -A CIOsuitabilityChecks=( \
  [SCscore]="License" \
  [HCscore]="${__NOCHECK__}" \
  [PHYscore]="license" \
  [MYscore]="ProjectRestrictiveLicense DepProjectsRestrictiveLicense TertiaryProjectsRestrictiveLicense" \
  )

declare -A CIOsuitabilityScores=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${__NAN__}" \
  [HCscore]="${__NAN__}" \
  [PHYscore]="${__NAN__}" \
  [MYscore]="${__NAN__}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A CIOsuitabilityWeights=( \
  [CIOscore]="${__NAN__}" \
  [SCscore]="${SCcritical}" \
  [HCscore]="${SCcritical}" \
  [PHYscore]="${SCcritical}" \
  [MYscore]="${SCcritical}" \
  )

#
# Scorecards (MY, SC, HC, PHY) checks tables
#

#
# this one is populated dynamically
#
declare -A SCcheckScores

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A SCcheckLabels=( \
  [Binary-Artifacts]="Binary Artifacts" \
  [Branch-Protection]="Branch Protection" \
  [CI-Tests]="CI Tests" \
  [CII-Best-Practices]="CII Best Practices" \
  [Code-Review]="Code Review" \
  [Contributors]="Contributors" \
  [Dangerous-Workflow]="Dangerous Workflow" \
  [Dependency-Update-Tool]="Dependency Update Tool" \
  [Fuzzing]="Fuzzing" \
  [License]="License" \
  [Maintained]="Maintained" \
  [Packaging]="Packaging" \
  [Pinned-Dependencies]="Pinned Dependencies" \
  [SAST]="SAST" \
  [Security-Policy]="Security Policy" \
  [Signed-Releases]="Signed Releases" \
  [Token-Permissions]="Token Permissions" \
  [Vulnerabilities]="Vulnerabilities" \
  [Webhooks]="Webhooks" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A SCcheckWeights=( \
  [Binary-Artifacts]="${SChigh}" \
  [Branch-Protection]="${SChigh}" \
  [CI-Tests]="${SClow}" \
  [CII-Best-Practices]="${SClow}" \
  [Code-Review]="${SChigh}" \
  [Contributors]="${SClow}" \
  [Dangerous-Workflow]="${SCcritical}" \
  [Dependency-Update-Tool]="${SChigh}" \
  [Fuzzing]="${SCmedium}" \
  [License]="${SClow}" \
  [Maintained]="${SChigh}" \
  [Packaging]="${SCmedium}" \
  [Pinned-Dependencies]="${SCmedium}" \
  [SAST]="${SCmedium}" \
  [Security-Policy]="${SCmedium}" \
  [Signed-Releases]="${SChigh}" \
  [Token-Permissions]="${SChigh}" \
  [Vulnerabilities]="${SChigh}" \
  [Webhooks]="${SCcritical}" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A SCcheckThresholds=( \
  [Binary-Artifacts]="${_SCthreshold}" \
  [Branch-Protection]="${_SCthreshold}" \
  [CI-Tests]="${_SCthreshold}" \
  [CII-Best-Practices]="${_SCthreshold}" \
  [Code-Review]="${_SCthreshold}" \
  [Contributors]="${_SCthreshold}" \
  [Dangerous-Workflow]="${_SCthreshold}" \
  [Dependency-Update-Tool]="${_SCthreshold}" \
  [Fuzzing]="${_SCthreshold}" \
  [License]="${_SCthreshold}" \
  [Maintained]="${_SCthreshold}" \
  [Packaging]="${_SCthreshold}" \
  [Pinned-Dependencies]="${_SCthreshold}" \
  [SAST]="${_SCthreshold}" \
  [Security-Policy]="${_SCthreshold}" \
  [Signed-Releases]="${_SCthreshold}" \
  [Token-Permissions]="${_SCthreshold}" \
  [Vulnerabilities]="${_SCthreshold}" \
  [Webhooks]="${_SCthreshold}" \
  )

#
# these two are populated dynamically
#
declare -A HCcheckScores

declare -A HCcheckThresholds

declare -A HCcheckLabels=( \
  [Activity]="Commit Activity" \
  [Binary]="Binary Artifacts" \
  [Churn]="Large Commits" \
  [Identity]="Self Reviews" \
  [Affiliation]="Author Affiliation" \
  [Entropy]="Malware Entropy" \
  [Fuzz]="Fuzz Testing" \
  [Review]="Pull Reviews" \
  [Typo]="Typosquatting" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A HCcheckWeights=( \
  [Activity]="${SChigh}" \
  [Binary]="${SChigh}" \
  [Churn]="${SChigh}" \
  [Identity]="${SChigh}" \
  [Affiliation]="${SCcritical}" \
  [Entropy]="${SChigh}" \
  [Fuzz]="${SCmedium}" \
  [Review]="${SChigh}" \
  [Typo]="${SChigh}" \
  )

#
# these two are populated dynamically
#
declare -A PHYcheckScores

declare -A PHYcheckThresholds

declare -A PHYcheckLabels=( \
  [author]="Malicious Author" \
  [license]="License" \
  [engineering]="Engineering" \
  [malicious_code]="Malicious Code" \
  [vulnerability]="Vuls" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A PHYcheckWeights=( \
  [total]="${__NAN__}" \
  [author]="${SCcritical}" \
  [license]="${SClow}" \
  [engineering]="${SChigh}" \
  [malicious_code]="${SChigh}" \
  [vulnerability]="${SChigh}" \
  )

declare -A MYcheckScores=( \
  [UnfixedVulnerabilities]="${__NAN__}" \
  [ProjectForked]="false" \
  [ProblemReporting]="false" \
  [DepProjectsForked]="${__NAN__}" \
  [TertiaryProjectsForked]="${__NAN__}" \
  [ProjectAbandoned]="false" \
  [DepProjectsAbandoned]="0" \
  [TertiaryProjectsAbandoned]="${__NAN__}" \
  [ProjectRestrictiveLicense]="${__NAN__}" \
  [DepProjectsRestrictiveLicense]="${__NAN__}" \
  [TertiaryProjectsRestrictiveLicense]="${__NAN__}" \
  )

declare -A MYcheckLabels=( \
  [UnfixedVulnerabilities]="Unfixed Vuls" \
  [ProjectForked]="Project Forked" \
  [ProblemReporting]="Problem Reporting" \
  [DepProjectsForked]="Dependent Projects Forked" \
  [TertiaryProjectsForked]="Other Projects Forked" \
  [ProjectAbandoned]="Project Abandoned" \
  [DepProjectsAbandoned]="Dependent Projects Abandoned" \
  [TertiaryProjectsAbandoned]="Other Projects Abandoned" \
  [ProjectRestrictiveLicense]="Restrictive License(s)" \
  [DepProjectsRestrictiveLicense]="Dependent Restrictive License(s)" \
  [TertiaryProjectsRestrictiveLicense]="Other Restrictive License(s)" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A MYcheckWeights=( \
  [UnfixedVulnerabilities]="${SCcritical}" \
  [ProjectForked]="${SCcritical}" \
  [ProblemReporting]="${SCcritical}" \
  [DepProjectsForked]="${SCmedium}" \
  [TertiaryProjectsForked]="${SClow}" \
  [ProjectAbandoned]="${SCcritical}" \
  [DepProjectsAbandoned]="${SChigh}" \
  [TertiaryProjectsAbandoned]="${SClow}" \
  [ProjectRestrictiveLicense]="${SCcritical}" \
  [DepProjectsRestrictiveLicense]="${SChigh}" \
  [TertiaryProjectsRestrictiveLicense]="${SClow}" \
  )

declare -A MYcheckThresholds=( \
  [UnfixedVulnerabilities]="0" \
  [ProjectForked]="false" \
  [ProblemReporting]="true" \
  [DepProjectsForked]="0" \
  [TertiaryProjectsForked]="0" \
  [ProjectAbandoned]="false" \
  [DepProjectsAbandoned]="0" \
  [TertiaryProjectsAbandoned]="0" \
  [ProjectRestrictiveLicense]="0" \
  [DepProjectsRestrictiveLicense]="0" \
  [TertiaryProjectsRestrictiveLicense]="0" \
  )

declare -A foundLicenses

declare -A licenseChecks

#
# helper to emit (or not) a red flag
# (flag on the play)
#
# added a return code (_rc)
# 0: no flag on the play, passed lt/gt/le/ge test
# 1: flag on the play, warning flag issued
# 2: flag on the play, red flag issued
#
_fotp()
{
  local _t='<='
  local _r=""
  local _dblspace=""
  local _flag="${__REDFLAG__}"
  local _rc=0

  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --dblSpace ]] && _dblspace="&nbsp;&nbsp;"
    [[ ${1} == --warnFlag ]] && _flag="${__WARNING__}"
    shift 1
  done


  [[ "${1}" == "${__CHECKNOTIMPL__}" ]] && echo "${__WARNING__}" && return 1
  [[ "${1}" == "-1" ]] && echo "${__WARNING__}" && return 1
  [[ "${1}" == "${__NAN__}" ]] && echo "${__WARNING__}" && return 1

  [[ "${2}" == "false" ]] || [[ "${2}" == "true" ]] && {
    [[ "${1}" != "${2}" ]] && _dblspace="" && _r="${_flag}" && _rc=2 && [[ "${_r}" == "${__WARNING__}" ]] && _rc=1
    echo -n "${_dblspace}${_r}";
    return ${_rc};
  }

  [[ "${3}" == "lt" ]] && _t='<'
  [[ "${3}" == "gt" ]] && _t='>'
  [[ "${3}" == "ge" ]] && _t='>='

  if (( $(echo "${1} ${_t} ${2}" | bc -l) )); then _dblspace="" && _r="${_flag}"; fi
  echo -n "${_dblspace}${_r}"

  [[ -n "${_r}" ]] && _rc=2 && [[ "${_r}" == "${__WARNING__}" ]] && _rc=1

  return ${_rc};
}

#
# floating point pretty print helper
_fppp()
{
  local _digits
  local _fpn

  _fpn="${2}"

  [[ ! ${_fpn} =~ ${_fpdigitsRE} ]] || [[ -z "${_fpn}" ]] && echo -n "${_fpn}" && return

  _digits="${1}"
  [[ "${_digits,,}" == "auto" ]] && if [[ ( $(( 64#${_fpn/*.} - 0)) == 0 ) ]]; then
    _digits=1
  else
    local _d
    _d=${_fpn/*.}
    for i in $(seq 0  $(( ${#_d} -1 )) ); do [[ ${_d:$i:1} != "0" ]] && break; done;
    _digits=$(( i+1 ));
  fi;

  printf "%.${_digits}f" "${_fpn}"
}

_as_of()
{
  local now
  local rpt

  now=$(date +%s)
  rpt=$(stat --printf=%Y "${1}") 
  echo "$(( (now-rpt) / 60 / 60 / 24 )) days ago"
  return
}

_set_thresholds()
{
  local _th

  # Scorecard
  #
  _warn "Thresholds for OSSF Scorecard scores set at ${_SCthreshold}"

  #
  # Criticality Score
  _warn "Threshold for OSSF Criticality Score set at ${_CSthreshold}"

  # Hipcheck
  #

  # Phylum
  #
  _th="$(jq -r '.riskThresholdActions.total.threshold' "${3}")"
  _msg="Thresholds for Phylum set in Phylum.io project account"
  [[ "${_th}" == "null" ]] && _msg="Thresholds for Phylum package URI scores set to ${_PHthreshold}"
  _warn "${_msg}"

  # OSS-P4/R
  #
  _warn "Local cache tolerance set to ${_cache_days} days"
  _warn "Days active tolerance set to ${__ACTIVEDAYS__} days"
  _warn "Days for a new project set to ${__DAYSNEW__} days"
  _warn "Contributors tolerance set to ${__CONTRIBCNT__} ids"
  _warn "Some responses require manual investigation if necessary"

  return
}

_compute_wScore()
{
  local card="${1}"
  local -n ckScore="${2}"
  local -n ckThres="${3}"
  local -n ckWeigh="${4}"
  shift 4

  local _pt=""
  local _sc=""
  local _wt=""
  local _theScore=""

  _theScore="${__NAN__}"

  for check in "${@}"
  do
    [[ "${check}" == "${__NOCHECK__}" || "${ckScore[$check]}" == "${__CHECKNOTIMPL__}" || "${ckScore[$check]}" == "${__NAN__}" || -z "${ckScore[$check]}" ]] && continue

    #
    # where necessary, convert into 0-10 pt scale
    #
    case "${card}" in
      HCscore | MYscore)
        _pt=$(_scale_raw_score "${ckScore[$check]}" "${ckThres["${check}"]}")
        ;;
      PHYscore)
        _pt=$(echo "(${PHYcheckScores[$check]} * 10)" | bc -l)
        ;;
      SCscore | P4score | CIOscore)
        _pt="${ckScore[$check]}"
        ;;
      *)
        _warn "invalid card: ${card}"
        ;;
    esac


    if [ -z "${_sc}" ]; then
      _sc="(${_pt}*${ckWeigh[$check]})"
      _wt="${ckWeigh[$check]}"
    else
      _sc="${_sc}+(${_pt}*${ckWeigh[$check]})"
      _wt="${_wt}+${ckWeigh[$check]}"
    fi
  done

  [[ -n "${_wt}" ]] && {
    _theScore="$(_fppp 1 "$(echo "( ( ${_sc} ) / ( ${_wt} ) )" | bc -l)")";
  }

  echo "${_theScore}"
  return
}

#
# implement the excel formula:
#
# =max(
#    (1-(
#      OR(threshold=0,threshold=TRUE,threshold=FALSE),
#        IF(raw_score=threshold,0,1)
#          ,raw_score/threshold))
#    ,0
#  ) * 10
#
# which becomes:
# =(1-(pct_of_threshold))*10
#
_scale_raw_score()
{
  local _pct
  local _raw
  local _thr

  _raw="${1}"
  _thr="${2}"

  #
  # test for 0 (int), 0.0 (float), false, true
  #
  if [[ ${_thr,,} =~ ^(0|[0]+\.?[0]*$|false|true)$ ]]; then
    _pct="1.0"
    [[ "${_raw,,}" == "${_thr,,}" ]] && _pct="0.0"
  else
    _pct="$(echo "(${_raw}/${_thr})" | bc -l)";
  fi

  echo "define max(x,y) { if ( x >= y ) return (x); return (y) }; ( max(1.0-( ${_pct} ),0) * 10.0 )" | bc -l
  return
}

jq_legacyPhylumScores()
{
  local __myphyc

  jq -r '.riskScores|to_entries|map("\(.key)=\(.value|tostring)")|.[]' "${1}"

  return 0
}

jq_newPhylumScores()
{
  local __myphyc

  for __myphyc in total vulnerability malicious_code author engineering license
  do
    echo -n ${__myphyc}=; jq -r "[.dependencies[].riskScores]|[.[].${__myphyc}]|min" "${1}"
  done

  return 0
}

_compute_p4_scores()
{
  local check
  local score

  [ ${#SCcheckScores[@]} -gt 0 ] && return

  _say -n "Computing scores for SC, "

  #
  # grab scores from scorecard checks
  if ${__ghSKIP}; then
    _SCcompositeScore="not run as project is not on GitHub unknown"
    PFourPolicyScores[SCscore]="unknown"
    PFourProjectScores[SCscore]="unknown"
    PFourProtectionScores[SCscore]="unknown"
    PFourProductScores[SCscore]="unknown"
    CIOlongTermScores[SCscore]="unknown"
    CIOdependencyScores[SCscore]="unknown"
    CIOsecurityScores[SCscore]="unknown"
    CIOintegrityScores[SCscore]="unknown"
    CIOmalActorsScores[SCscore]="unknown"
    CIOsuitabilityScores[SCscore]="unknown"
  else #{
    while IFS="=" read -r check score
    do
      [[ "${score}" == "${SCfail}" || -z "${score}" ]] && score="${__NAN__}"
      SCcheckScores["${check}"]="${score}"
    done < <(jq -r '.checks[]|[.name,"=",.score]|@csv' "${1}" | sed 's/[",]//g')
    #
    # the loop above assumes all checks were "run" for scorecard
    # webhooks may not have run this works around that
    [[ -z "${SCcheckScores[Webhooks]}" ]] && SCcheckScores[Webhooks]="${__NAN__}"

    #
    # these scores are defined by local context and not OSSF
    #
    # shellcheck disable=2086
    CIOlongTermScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${CIOlongTermChecks[SCscore]})

    # shellcheck disable=2086
    CIOdependencyScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${CIOdependencyChecks[SCscore]})

    # shellcheck disable=2086
    CIOsecurityScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${CIOsecurityChecks[SCscore]})

    # shellcheck disable=2086
    CIOintegrityScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${CIOintegrityChecks[SCscore]})

    # shellcheck disable=2086
    CIOmalActorsScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${CIOmalActorsChecks[SCscore]})

    # shellcheck disable=2086
    CIOsuitabilityScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${CIOsuitabilityChecks[SCscore]})

    # shellcheck disable=2086
    PFourPolicyScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${PFourPolicyChecks[SCscore]})

    # shellcheck disable=2086
    PFourProjectScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${PFourProjectChecks[SCscore]})

    # shellcheck disable=2086
    PFourProtectionScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${PFourProtectionChecks[SCscore]})

    # shellcheck disable=2086
    PFourProductScores[SCscore]=$(_compute_wScore \
            SCscore SCcheckScores SCcheckThresholds SCcheckWeights ${PFourProductChecks[SCscore]})

    #
    # this is the overall OSSF Score
    #
    _SCcompositeScore=$(jq -r '.score' "${1}")
  fi #}

  _say -n "HC, "

  #
  # grab scores from Hipcheck checks
  if ${__ghSKIP}; then
    _HCscore="not run as project is not on GitHub unknown"
    _HCrationale="unknown"
    PFourPolicyScores[HCscore]="unknown"
    PFourProjectScores[HCscore]="unknown"
    PFourProtectionScores[HCscore]="unknown"
    PFourProductScores[HCscore]="unknown"
    CIOlongTermScores[HCscore]="unknown"
    CIOdependencyScores[HCscore]="unknown"
    CIOsecurityScores[HCscore]="unknown"
    CIOintegrityScores[HCscore]="unknown"
    CIOmalActorsScores[HCscore]="unknown"
    CIOsuitabilityScores[HCscore]="unknown"
  else #{
    while IFS="=" read -r check score threshold
    do
      # use NaN to signify errored check
      [[ -z "${score}" ]] && score="${__NAN__}"
      #
      # shell check 0.8.0 seems to rightly calling the
      # assignment a noop and this should be removed
      # TODO: deeper review to "ok" removing this line
      # shellcheck disable=2269
      #
      [[ ${score} =~ ${_fpdigitsRE} ]] && score="${score}"
      # hipchecks only true/false check has no threshold
      # but false is bad and implicitly implies true is
      # the threshold
      [[ -z "${threshold}" ]] && threshold="true"
      HCcheckScores["${check}"]="${score}"
      HCcheckThresholds["${check}"]="${threshold}"
    done < <(
    { \
      jq -r '.passing[]|[.analysis,"=",.value,"=",.threshold]|@csv' "${2}" ; \
      jq -r '.failing[]|[.analysis,"=",.value,"=",.threshold]|@csv' "${2}" ; \
      jq -r '.errored[]|[.analysis,"=",.value,"=",.threshold]|@csv' "${2}" ; \
    } | sed 's/[",]//g') 

    _HCrationale=$(jq -r '.rationale|@base64d' "${2}" |
      grep Recommendation -A 1 |
      tail -1 |
      tr -d '\r' |
      sed 's/^[ \t]*//;s/[ \t]*$//'
    )
    _HCscore=$(cut -d, -f1 < <(echo "${_HCrationale}") |cut -d\   -f5)
    _HCrationale="$(_fotp "${_HCthreshold}" "${_HCscore}")${_HCrationale}"

    # shellcheck disable=2086
    CIOlongTermScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${CIOlongTermChecks[HCscore]})

    # shellcheck disable=2086
    CIOdependencyScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${CIOdependencyChecks[HCscore]})

    # shellcheck disable=2086
    CIOsecurityScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${CIOsecurityChecks[HCscore]})

    # shellcheck disable=2086
    CIOintegrityScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${CIOintegrityChecks[HCscore]})

    # shellcheck disable=2086
    CIOmalActorsScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${CIOmalActorsChecks[HCscore]})

    # shellcheck disable=2086
    CIOsuitabilityScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${CIOsuitabilityChecks[HCscore]})

    # shellcheck disable=2086
    PFourPolicyScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${PFourPolicyChecks[HCscore]})

    # shellcheck disable=2086
    PFourProjectScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${PFourProjectChecks[HCscore]})

    # shellcheck disable=2086
    PFourProtectionScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${PFourProtectionChecks[HCscore]})

    # shellcheck disable=2086
    PFourProductScores[HCscore]=$(_compute_wScore \
            HCscore HCcheckScores HCcheckThresholds HCcheckWeights ${PFourProductChecks[HCscore]})
  fi #}

  #
  # on or about 1 JUN, Phylum removed overall riskScores in their json
  # use here. At the same time totalRiskScore was also removed.
  # Here sense if the json file is the "old" version (pre JUNE 2024)
  # or the new version (not having totalRiskScore) and adapt.
  #
  # These scores are close to being the min value of all the
  # domain/category scores for all the dependencies.
  # TODO: revise the "min"imum approach used here to replace
  #       the now defunct riskScores which used to be in the
  #       Phylum json file - but still support the old format
  #       for regression testing. Would be nice if the json
  #       struct itself was version (including the REST API)
  #
  local __phyJQ
  local __phyVersion=" (legacy), "
  __phyJQ='jq_legacyPhylumScores'
  grep -s -q totalRiskScore "${3}" || { __phyJQ='jq_newPhylumScores' && __phyVersion=", "; }

  _say -n "PHY${__phyVersion}"

  #
  # grab scores from Phylum.io checks
  while IFS="=" read -r check score
  do
    #
    # this is ONLY true (score should ne NaN) if the
    # top-level component was pulled using (-P) a
    # phylum project which are analyzed. If pulled
    # using package URI (-U) this will always be 'null'
    #
    [[ ${puri} == "${__NULLPURI__}" ]] && [[ $(jq -r '.latestJobId' "${3}") == "null" ]] && score="${__NAN__}"
    PHYcheckScores["${check}"]="$(_fppp 2 "${score}")"
    #
    # threholds were in the old json format, these are not there, but this will default
    # to the defaults in _PHthreshold
    PHYcheckThresholds["${check}"]="$(jq --arg _c "${check}" -r '.riskThresholdActions|.[$_c].threshold' "${3}")"
    [[ "${PHYcheckThresholds["${check}"]}" == "null" ]] && PHYcheckThresholds["${check}"]="${_PHthreshold}"
  done < <("${__phyJQ}" "${3}")

  # shellcheck disable=2086
  CIOlongTermScores[PHYscore]=$(_compute_wScore \
            PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${CIOlongTermChecks[PHYscore]})
  # shellcheck disable=2086
  CIOdependencyScores[PHYscore]=$(_compute_wScore \
            PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${CIOdependencyChecks[PHYscore]})
  # shellcheck disable=2086
  CIOsecurityScores[PHYscore]=$(_compute_wScore \
            PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${CIOsecurityChecks[PHYscore]})
  # shellcheck disable=2086
  CIOintegrityScores[PHYscore]=$(_compute_wScore \
            PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${CIOintegrityChecks[PHYscore]})
  # shellcheck disable=2086
  CIOmalActorsScores[PHYscore]=$(_compute_wScore \
            PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${CIOmalActorsChecks[PHYscore]})
  # shellcheck disable=2086
  CIOsuitabilityScores[PHYscore]=$(_compute_wScore \
            PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${CIOsuitabilityChecks[PHYscore]})

  # shellcheck disable=2086
  PFourPolicyScores[PHYscore]=$(_compute_wScore \
          PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${PFourPolicyChecks[PHYscore]})
  # shellcheck disable=2086
  PFourProjectScores[PHYscore]=$(_compute_wScore \
          PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${PFourProjectChecks[PHYscore]})
  # shellcheck disable=2086
  PFourProtectionScores[PHYscore]=$(_compute_wScore \
          PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${PFourProtectionChecks[PHYscore]})
  # shellcheck disable=2086
  PFourProductScores[PHYscore]=$(_compute_wScore \
          PHYscore PHYcheckScores PHYcheckThresholds PHYcheckWeights ${PFourProductChecks[PHYscore]})

  _say -n "MY, "

  #
  # grab scores from MYchecks checks
  if ${__ghSKIP}; then
    PFourPolicyScores[MYscore]="unknown"
    PFourProjectScores[MYscore]="unknown"
    PFourProtectionScores[MYscore]="unknown"
    PFourProductScores[MYscore]="unknown"
    CIOlongTermScores[MYscore]="unknown"
    CIOdependencyScores[MYscore]="unknown"
    CIOsecurityScores[MYscore]="unknown"
    CIOintegrityScores[MYscore]="unknown"
    CIOmalActorsScores[MYscore]="unknown"
    CIOsuitabilityScores[MYscore]="unknown"
  else
    # shellcheck disable=2086
    CIOlongTermScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${CIOlongTermChecks[MYscore]})

    # shellcheck disable=2086
    CIOdependencyScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${CIOdependencyChecks[MYscore]})

    # shellcheck disable=2086
    CIOsecurityScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${CIOsecurityChecks[MYscore]})

    # shellcheck disable=2086
    CIOintegrityScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${CIOintegrityChecks[MYscore]})

    # shellcheck disable=2086
    CIOmalActorsScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${CIOmalActorsChecks[MYscore]})

    # shellcheck disable=2086
    CIOsuitabilityScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${CIOsuitabilityChecks[MYscore]})

    # shellcheck disable=2086
    PFourPolicyScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${PFourPolicyChecks[MYscore]})

    # shellcheck disable=2086
    PFourProjectScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${PFourProjectChecks[MYscore]})

    # shellcheck disable=2086
    PFourProtectionScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${PFourProtectionChecks[MYscore]})

    # shellcheck disable=2086
    PFourProductScores[MYscore]=$(_compute_wScore \
            MYscore MYcheckScores MYcheckThresholds MYcheckWeights ${PFourProductChecks[MYscore]})
  fi

  _say -n "CIO, "
  #
  # now, compute overall criteria scores
  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  CIOlongTermScores[CIOscore]=$(_compute_wScore \
          CIOscore CIOlongTermScores "${__NAN__}" CIOlongTermWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  CIOdependencyScores[CIOscore]=$(_compute_wScore \
          CIOscore CIOdependencyScores "${__NAN__}" CIOdependencyWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  CIOsecurityScores[CIOscore]=$(_compute_wScore \
          CIOscore CIOsecurityScores "${__NAN__}" CIOsecurityWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  CIOintegrityScores[CIOscore]=$(_compute_wScore \
          CIOscore CIOintegrityScores "${__NAN__}" CIOintegrityWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  CIOmalActorsScores[CIOscore]=$(_compute_wScore \
          CIOscore CIOmalActorsScores "${__NAN__}" CIOmalActorsWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  CIOsuitabilityScores[CIOscore]=$(_compute_wScore \
          CIOscore CIOsuitabilityScores "${__NAN__}" CIOsuitabilityWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  _say -n "and P4 "

  #
  # finally, compute overall score
  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  PFourPolicyScores[P4score]=$(_compute_wScore \
          P4score PFourPolicyScores "${__NAN__}" PFourPolicyScoresWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  PFourProjectScores[P4score]=$(_compute_wScore \
          P4score PFourProjectScores "${__NAN__}" PFourProjectScoresWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  PFourProtectionScores[P4score]=$(_compute_wScore \
          P4score PFourProtectionScores "${__NAN__}" PFourProtectionScoresWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  # shell checker does not see this is passed by ref
  # shellcheck disable=2034
  PFourProductScores[P4score]=$(_compute_wScore \
          P4score PFourProductScores "${__NAN__}" PFourProductScoresWeights \
          "SCscore" "HCscore" "PHYscore" "MYscore")

  _HTMLfootnotes+=("<b>**Data in this report is from public sources and with some being self-reported (e.g., emails, country of origin, names)**</b>.<br/>")
  _HTMLfootnotes+=("<b>Pending/manual</b>: <i>Check requires manual intervention</i>.<br/>")
  _HTMLfootnotes+=("<b>Restrictive license</b>: <i>A license that requires code changes be openly published (i.e., copyleft)</i>.<br/>")
  _HTMLfootnotes+=("${__WARNING__}<b>-1/n</b>: <i>Score could not be valued due to source data</i>.<br/>")
  _HTMLfootnotes+=("${__WARNING__}<b>${__NAN__}</b>: <i>Score could not be computed due to source data</i>.<br/>")
  _HTMLfootnotes+=("${__WARNING__}<b>n</b>: <i>Score indicated a possible risk which requires investigation</i>.<br/>")
  _HTMLfootnotes+=("${__WARNING__}<b> not checked</b>: <i>Check is coming soon</i>.<br/>")
  _HTMLfootnotes+=("${__REDFLAG__}<b>m/n</b>: <i>Score did not meet goals and/or thresholds</i>.<br/>")
  _HTMLfootnotes+=("${__REDFLAG__}<b>n</b>: <i>Score did not meet goals and/or thresholds</i>.<br/>")
  _HTMLfootnotes+=("${__REDFLAG__}<b>Yes/No</b>: <i>Score did not meet goals and/or thresholds</i>.<br/>")
  _HTMLfootnotes+=("${__REDFLAG__}<b>true/false</b>: <i>Score did not meet goals and/or thresholds</i>.<br/>")

  _say "done."

  return
}

_rgb_score()
{
  local _s
  local _t

  _s="${1}"
  _t="${2}"

  [[ "${_s}" == "${__NAN__}" ]] && echo "rgba(255, 255, 255, 1.0)" && return

  echo "rgba($(_fppp 0 "$(echo "define min(x,y) { if ( x <= y ) return (x); return (y) }; min(2-2*(${_s}/${_t}),1)*255" | bc -l)"), $(_fppp 0 "$(echo "define min(x,y) { if ( x <= y ) return (x); return (y) }; min(2*(${_s}/${_t}),1)*255" | bc -l)"), 0, 1.0)"
  return
}

_confhtml_wrapper_start()
{
  echo "<div class='content-wrapper'>"
  return
}

_confhtml_wrapper_end()
{
  echo "</div>"

  return
}

_wwwhtml_wrapper_start()
{
  return
}

_wwwhtml_wrapper_end()
{
  return
}

_confhtml_table_start()
{
  echo "<ac:structured-macro ac:name='table' ac:schema-version='1'> <ac:parameter ac:name='summary'>test</ac:parameter> <ac:parameter ac:name='id'>${1}</ac:parameter> <ac:parameter ac:name='dir'>ltr</ac:parameter> <ac:parameter ac:name='title'>${1}</ac:parameter> <ac:rich-text-body>"
  return
}

_confhtml_table_end()
{
  echo "</ac:rich-text-body> </ac:structured-macro>"
  return
}

_wwwhtml_table_start()
{
  local q
  local _col=1

  [[ "${2/=*}" == "col" ]] && _col="${2/col=}"

  echo "<table class='wrapped' data-mce-resize='false'><colgroup>"
  for (( q=0; q < _col; ++q))
  do
    echo "<col/>"
  done
  echo "</colgroup>"
  echo "<tbody>"
  return
}

_wwwhtml_table_end()
{
  echo "</tbody></table>"
  return
}

_confhtml_tablerow_start()
{
  echo "<ac:structured-macro ac:name='tr' ac:schema-version='1'> <ac:rich-text-body>"
  return
}

_confhtml_tablerow_end()
{
  echo "</ac:rich-text-body> </ac:structured-macro>"
  return
}

_wwwhtml_tablerow_start()
{
  #echo "<tr><td>${1}</td>"
  echo "<tr>"
  return
}

_wwwhtml_tablerow_end()
{
  echo "</tr>"
  return
}

_confhtml_tabledata_start()
{
  local _col
  local _bg
  local _v

  _col="<ac:parameter ac:name='colspan'>1</ac:parameter>"
  _bg=""
  _v="${1}"

  [[ "${2/=*}" == "col" ]] && _col="<ac:parameter ac:name='colspan'>${2/col=}</ac:parameter>"
  [[ "${2/=*}" == "bg" ]] && _bg="<ac:parameter ac:name='style'>background-color:${2/bg=};</ac:parameter>"

  echo "<ac:structured-macro ac:name='td' ac:schema-version='1'> ${_col} ${_bg} <ac:rich-text-body> $([[ "${_v}" =~ NaN ]] && echo "&nbsp;" || echo "${_v}") "
  return
}

_confhtml_tabledata_end()
{
  echo "</ac:rich-text-body> </ac:structured-macro>"
  return
}

_wwwhtml_tabledata_start()
{
  local _beg
  local _v

  _beg="<td>"
  _v="${1}"

  [[ "${1/=*}" == "hdr" ]] && {
    _v="${1/hdr=}";
    [[ -n ${_v} ]] && _beg="<th>";
  }
 
  echo "${_beg}${_v}"
  return
}

_wwwhtml_tabledata_end()
{
  local _end

  _end="</td>"
  echo "${_end}"
  return
}

_cio_criteria()
{
  local tblhtml_data
  local _card
  local _rowname
  local _label
  local _cols

  _cols=7

  tblhtml_data=$(
cat <<-_TBLHTMLEOF
$(_confhtml_wrapper_start)
  $(_confhtml_table_start "CIO Criteria")
      $(for _card in "Criteria:CIOscore" "__SECTION__:__SECTION__" "MY_Checks:MYscore" "OSSF_Scorecard:SCscore" "MITRE_Hipcheck:HCscore" "Phylum_io:PHYscore"
      do
        _confhtml_tablerow_start "${_card/*:}"
        _rowname="${_card/:*}"
        for _label in "${_rowname}" Security:CIOsecurityScores Integrity:CIOintegrityScores Dependencies:CIOdependencyScores Malicious_Actors:CIOmalActorsScores Long-Term_Support:CIOlongTermScores Suitability:CIOsuitabilityScores
        do
           [[ "${_card/*:}" == "__SECTION__" ]] && \
             _confhtml_tabledata_start "${__SECTION__}" "col=${_cols}" && \
             _confhtml_tabledata_end && \
             _confhtml_tablerow_end && \
             continue 2
           if [[ -n "${_rowname}" ]]; then
             _confhtml_tabledata_start "${_rowname/_/ }" && _rowname=
           else
             unset -n _aarray; local -n _aarray; _aarray="${_label/*:}"
             local _colname="${_label/:*}"
             _confhtml_tabledata_start "${_colname//_/ } (${_aarray[${_card/*:}]})" "bg=$(_rgb_score "${_aarray[${_card/*:}]}" "10.0")"
           fi
           _confhtml_tabledata_end
        done
        _confhtml_tablerow_end
      done)
  $(_confhtml_table_end)
$(_confhtml_wrapper_end)
_TBLHTMLEOF
)

  echo "${tblhtml_data}"
  return
}

_p4_outlook()
{
  local althtml_data
  local _card
  local _rowname
  local _label
  local _cols

  _cols=5

  althtml_data=$(
cat <<-_ALTHTMLEOF
$(_confhtml_wrapper_start)
  $(_confhtml_table_start "P4 Outlook")
      $(for _card in "Overall:P4score" "__SECTION__:__SECTION__" "MY_Checks:MYscore" "OSSF_Scorecard:SCscore" "MITRE_Hipcheck:HCscore" "Phylum_io:PHYscore"
      do
        _confhtml_tablerow_start "${_card/*:}"
        _rowname="${_card/:*}"
        for _label in "${_rowname}" Project:PFourProjectScores Product:PFourProductScores Protection:PFourProtectionScores Policy:PFourPolicyScores
        do
           [[ "${_card/*:}" == "__SECTION__" ]] && \
             _confhtml_tabledata_start "${__SECTION__}" "col=${_cols}" && \
             _confhtml_tabledata_end && \
             _confhtml_tablerow_end && \
             continue 2
           if [[ -n "${_rowname}" ]]; then
             _confhtml_tabledata_start "${_rowname/_/ }" && _rowname=
           else
             unset -n _aarray; local -n _aarray; _aarray="${_label/*:}"
             local _colname="${_label/:*}"
             _confhtml_tabledata_start "${_colname//_/ } (${_aarray[${_card/*:}]})" "bg=$(_rgb_score "${_aarray[${_card/*:}]}" "10.0")"
           fi
           _confhtml_tabledata_end
        done
        _confhtml_tablerow_end
      done)
  $(_confhtml_table_end)
$(_confhtml_wrapper_end)
_ALTHTMLEOF
)

  echo "${althtml_data}"
  return
}

_summary_scores_criteria_tbl()
{
  local wwwtbl_data
  local _card
  local _tbl
  local _rowname
  local _label
  local _cols

  _cols=7

  wwwtbl_data=$(
cat <<-_WWWTBLEOF
$(_wwwhtml_wrapper_start)
  $(_wwwhtml_table_start "Scores by Criteria" "col=${_cols}")
      $(for _card in "Criteria:CIOscore" "__SECTION__:__SECTION__" "MY_Checks:MYscore" "OSSF_Scorecard:SCscore" "MITRE_Hipcheck:HCscore" "Phylum_io:PHYscore"
      do
        # for wwwhtml table (and not confhtml table) skip __SECTION__
        [[ "${_card/*:}" == "__SECTION__" ]] && continue
        _wwwhtml_tablerow_start "${_card/*:}"
        _tbl="${_card/*:}"
        _rowname="${_card/:*}"
        for _label in "${_rowname}" Security:CIOsecurityChecks Integrity:CIOintegrityChecks Dependencies:CIOdependencyChecks Malicious_Actors:CIOmalActorsChecks Long-Term_Support:CIOlongTermChecks Suitability:CIOsuitabilityChecks
        do
           [[ "${_card/*:}" == "__SECTION__" ]] && \
             _wwwhtml_tabledata_start "${__SECTION__}" "col=${_cols}" && \
             _wwwhtml_tabledata_end && \
             _wwwhtml_tablerow_end && \
             continue 2
           local _hdr=""
           local _fp=""
           local _tt=""
           local _bhr=""
           local _ehr=""
           local _mg=""
           case "${_card/*:}" in
             CIOscore)
               _hdr="${_label/:*}"; _hdr="${_hdr/_/ }"; ;;
             MYscore)
               _tt="gt"; ;;
             SCscore)
               _bhr="<a href='https://github.com/ossf/scorecard/blob/main/docs/checks.md'>";
               _ehr="</a>";
               _mg="(higher's better) $(_fotp "${_SCcompositeScore}" "${_SCthreshold}")${_SCcompositeScore}/10.0"; ;;
             HCscore)
               _tt="gt";
               _fp="auto";
               _bhr="<a href='https://github.com/mitre/hipcheck/blob/main/docs/book/src/using/analyses.md'>";
               _ehr="</a>";
               _mg="(score &le; threshold) ${_HCrationale}"; ;;
             PHYscore)
               _fp="2";
               _bhr="<a href='https://www.phylum.io/risk-philosophy'>";
               _ehr="</a>";
               _mg="(higher's better) $(_fotp "${PHYcheckScores[total]}" "${PHYcheckThresholds[total]}")${PHYcheckScores[total]}/1.0"; ;;
             *)
               _warn "invalid _card: ${_card/*:}"; ;;
           esac
           if [[ -n "${_rowname}" ]]; then
             _wwwhtml_tabledata_start "${_bhr}${_rowname/_/ }${_ehr}:<br/>${_mg}" && _rowname=
           else
             unset -n _aarray; local -n _aarray; _aarray="${_label/*:}"
             unset -n _sarray; declare -n _sarray; _sarray="${_tbl/score/checkScores}"
             unset -n _tarray; declare -n _tarray; _tarray="${_tbl/score/checkThresholds}"
             unset -n _larray; declare -n _larray; _larray="${_tbl/score/checkLabels}"
             local _colname="${_label/:*}"
             _wwwhtml_tabledata_start "${_hdr}"
             for _check in ${_aarray[${_card/*:}]}
             do
               [[ "${__NOCHECK__}" == "${_check}" ]] && break
               [[ "${__CHECKNOTIMPL__}" == "${_sarray[${_check}]}" ]] || [[ -z "${_sarray[${_check}]}" ]] && continue
               echo -n "$(_fotp "${_sarray["${_check}"]}" "${_tarray["${_check}"]}" "${_tt}")${_larray[${_check}]}($(_fppp "${_fp}" "${_sarray[${_check}]}")/${_tarray[${_check}]})<br/>"
             done
           fi
           _wwwhtml_tabledata_end
        done
        _wwwhtml_tablerow_end
      done)
  $(_wwwhtml_table_end)
$(_wwwhtml_wrapper_end)
_WWWTBLEOF
)

  echo "${wwwtbl_data}"
  return
}

_summary_scores()
{
  _say -n "Reporting Summary Scores..."

  local scmsg
  local hcmsg
  local phmsg
  local mymsg

  mymsg="MY Checks: "
  for check in "${!MYcheckScores[@]}"
  do
    #
    # only for MYchecks use __NAN__ as a flag for a check that is not implemented (yet)
    #
    [[ "${MYcheckScores["${check}"]}" == "${__NAN__}" ]] && continue
    mymsg="${mymsg}${MYcheckLabels["${check}"]} ($(_fotp "${MYcheckScores["${check}"]}" "${MYcheckThresholds["${check}"]}" gt)${MYcheckScores["${check}"]}/${MYcheckThresholds["${check}"]}), "
  done
  mymsg="${mymsg/%, /}"

  scmsg="<a href='https://github.com/ossf/scorecard/blob/main/docs/checks.md'>OSSF Scorecard</a>: (higher's better) $(_fotp "${_SCcompositeScore}" "${_SCthreshold}")${_SCcompositeScore}/10.0<br/>(composed of  "
  for check in "${!SCcheckScores[@]}"
  do
    scmsg="${scmsg}${SCcheckLabels["${check}"]} ($(_fotp "${SCcheckScores["${check}"]}" "${SCcheckThresholds["${check}"]}")${SCcheckScores["${check}"]}/${SCcheckThresholds["${check}"]}), "
  done
  scmsg="${scmsg/%, /})"

  hcmsg="<a href='https://github.com/mitre/hipcheck/blob/main/docs/book/src/using/analyses.md'>MITRE Hipcheck</a>: (score &le; threshold) ${_HCrationale}<br/>(composed of "
  for check in "${!HCcheckScores[@]}"
  do
    hcmsg="${hcmsg}${HCcheckLabels["${check}"]} ($(_fotp "${HCcheckScores["${check}"]}" "${HCcheckThresholds["${check}"]}" gt)$(_fppp "auto" ${HCcheckScores["${check}"]})/${HCcheckThresholds["${check}"]}), "
  done
  hcmsg="${hcmsg/%, /})"

  phmsg="<a href='https://www.phylum.io/risk-philosophy'>Phylum.io</a>: (higher's better) $(_fotp "${PHYcheckScores[total]}" "${PHYcheckThresholds[total]}")${PHYcheckScores[total]}/1.0<br/>(composed of "
  for check in "${!PHYcheckScores[@]}"
  do
    [[ "total" == "${check}" ]] && continue
    phmsg="${phmsg}${PHYcheckLabels["${check}"]} ($(_fotp "${PHYcheckScores["${check}"]}" "${PHYcheckThresholds["${check}"]}")${PHYcheckScores["${check}"]}), "
  done
  #
  # https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
  # removes the trailing ', ' of the last iteration of this prior for loop
  #
  phmsg="${phmsg/%, /})"

  _say "done."

  echo "<p>${mymsg}</p><p>${scmsg}</p><p>${hcmsg}</p><p>${phmsg}</p>"

  return
}

_background()
{
  local _parent

  ${__ghSKIP} && echo "Project is not on GitHub" && return

  [[ "${MYcheckScores[ProjectForked]}" != "${MYcheckThresholds[ProjectForked]}" ]] &&
    _parent="$(jq -rj '.parent.full_name' "${1}")";

  {
    jq -j '.full_name, ", ", .description|@html' "${1}" &&
      "${MYcheckScores[ProjectForked]}" &&
       echo "<br/>$(_fotp "${MYcheckScores[ProjectForked]}" "${MYcheckThresholds[ProjectForked]}" gt)ATTENTION: this is a fork of ${_parent}"
  } | iconv -c -f utf-8 -t ascii
  return
}

_user_org()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return
  #
  # TODO: make this information cached for offline mode
  #
  ${blockNetwork} && echo "Offline mode, realtime project data not available at this time" && return

  _ot="$(jq -j '.owner.type' "${1}")"
  _ou="$(jq -r '.owner.url' "${1}")"
  _od=$(curl --silent -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" "${_ou}" | \
    jq -r '.|["Name:",.name,"Company:",.company,"Bio:",.bio,"Email:",.email,"Blog:",.blog,"Geo:",.location,"Source:","GitHub"]|@csv|@html' 2>/dev/null | \
    sed 's/&quot;/"/g;s/,,/,Not Reported,/g;s/""/"Not Reported"/g;s/"//g;s/:,/: /g;s/,/, /g' | iconv -c -f utf-8 -t ascii)

  echo "${_ot}<p/>Details: ${_od//, /<br\/>}"
  return
}

_abandoned_prjs()
{
  local _ptxt

  _ptxt="is not"
  [[ "${MYcheckScores[ProjectAbandoned]}" == "true" ]] && _ptxt="is"

  echo "${1/_ghapi.json/} $(_fotp "${MYcheckScores[ProjectAbandoned]}" "${MYcheckThresholds[ProjectAbandoned]}")${_ptxt} archived; $(_fotp "${MYcheckScores[DepProjectsAbandoned]}" "${MYcheckThresholds[DepProjectsAbandoned]}" "gt")${MYcheckScores[DepProjectsAbandoned]} of the primary dependencies are abandoned; $(_fotp "-1")tertiary (other) dependencies are not checked at this time"

  return
}

_maintained()
{
  local _t
  local _v
  local _q

  if [ -s "${1}" ]; then
    _v="$(jq -r '.checks[]|select(.name=="Maintained")|.score' "${1}")"
    _scmsg="$(
    echo -n "$(_fotp "${_v}" "${_SCthreshold}")";
      jq -r '.checks[]|select(.name=="Maintained")|[.score," with ",.reason]|@csv' "${1}";
    )"
  else
    _scmsg="No insight from scorecard"
  fi

  # shellcheck disable=2046
  _hcmsg="with no insight from hipcheck"
  if [ -s "${2}" ]; then
    _v="$(jq -r '..|select(.analysis?=="Activity")|[.value,.threshold]|@csv' "${2}")"
    _t="${_v//*,/}"
    _v="${_v//,*/}"
    _q="under or at"
    [[ -n "${_v}" ]] && {
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over"
      _hcmsg="with most recent activity being ${_v} weeks ${_q} the ${_t} week threshold";
    }
  fi

  echo "${_scmsg} ${_hcmsg}" | sed 's/"//g;s/ ,/ /g'

  return
}
_maintainers()
{
  echo "Count pending"

  return
}

_contrib_count()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local _c
  
  _c=$(jq -r '.[]|.login' "${1}" |wc -l)
  [[ ${_c} -lt ${__CONTRIBCNT__} ]] && _c="${__WARNING__}${_c}"

  echo -n "${_c}"
  return
}

_contrib_org()
{
  local _co

  _co="$(jq -r '.checks[]|select(.name=="Contributors")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  if [[ -n "${_co}" ]]; then
    _co="$(_fotp "$(echo "${_co}" | cut -d, -f1)" "${_SCthreshold}")${_co}"
  else
    _co="${__WARNING__} check for contributor diversity not run"
  fi

  echo "${_co}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_sbom_val()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local _v

  #
  # assumes that this SBOM is from GitHub (the .sbom key)
  # and assumes the SBOM confirms to SPDX (the .spdxVersion)
  # TODO: auto-sense the SBOM format (e.g., spdx, syft,
  #       cycloneDX, etc.)
  _v=$(jq -r '[ .sbom.spdxVersion,.sbom.creationInfo.creators[0] ]|@csv' "${1}" | sed 's/null//g;s/"//g;s/,/, /g')
  [[ -z "${_v}" ]] && _v="manual";

  echo -n "${_v}"
  return
}

_day_last()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local rpt
  local last
  local days

  rpt=$(stat --printf=%Y "${1}") 
  # date +%s --date=2023-01-27T23:27:19Z
  last=$(date +%s --date="$(jq -j '.pushed_at' "${1}")")
  days="$(( (rpt-last) / 60 / 60 / 24 ))"
  echo "$(_fotp "${__ACTIVEDAYS__}" "${days}")${days} days, on $(date --date="$(jq -j '.pushed_at' "${1}")"), reported $(_as_of "${1}")"
  return
}

_day_first()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local rpt
  local created
  local days

  rpt=$(stat --printf=%Y "${1}") 
  created=$(date +%s --date="$(jq -r '.created_at' "${1}")")
  days="$(( (rpt-created) / 60 / 60 / 24 ))"
  echo "$(_fotp "${days}" "${__DAYSNEW__}")${days} days, on $(date --date="$(jq -j '.created_at' "${1}")"), reported $(_as_of "${1}")"
  return
}

_org_type()
{
  local _duns

  _duns=""
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  [[ $(jq -j '.owner.type' "${1}") == "Organization" ]] && _duns=" <br/>logistics database D-U-N-S code: Manual"

  echo "Pending, see: $(jq -r '.owner.organizations_url' "${1}")${_duns}"
  return
}

_slsa_level()
{
  local _lev

  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _slsa="$(grep -o -E '(alt=\\"SLSA[[:space:]][[:digit:]])' "${__ghhtml}")" && \
    { \
      echo "${_slsa/alt=\\\"/}"; \
      return; \
    }
  echo "Pending: (ask)"
  return
}

_criticality_score()
{
  local _cs

  ${blockNetwork} && [[ ! -s "${1}" ]] &&
    _warn "Offline mode, cannot run _criticality_score, skipped" &&
    _cs=${__NAN__} &&
    echo "$(_fotp --warnFlag "${_cs}" "${_CSthreshold}")$(_fppp "2" "${_cs}")/1.0" &&
    return 0

  [[ ! -s "${1}" ]] && {
    _warn "criticality score file ${1} missing, rebuilding...";
    #
    # TODO: this is duplicate code from what is in build_scorecards
    #       as this was added later and reports could be gen'ed
    #       when build_scorecards is NOT hit (dependencies or -p)
    #       so this is a temp solution, and should be removed
    #
    local _localdepdir;
    local _err;
    _err="${_localdepdir}"/"$(basename "${_localdepdir}")".cs.json.err;
    rm -f "${_err}";
    _localdepdir="deps.d/$(mkdepdir "${gh_site}")";
    _run_criticality_score "${gh_site}" "$(basename "${_localdepdir}")" "${_localdepdir}";
    [[ -s "${_err}" ]] && grep -q -E -o '("error": "repo failed:)' "${_err}" && \
      _warn "criticality score: ${gh_site} not found";
  }

  _cs="$(jq -r '.default_score' "${1}")"
  echo "$(_fotp --warnFlag "${_cs}" "${_CSthreshold}")$(_fppp "2" "${_cs}")/1.0"
  return
}

_best_practices()
{
  local _bp

  _bp="$(jq -r '.checks[]|select(.name=="CII-Best-Practices")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  if [[ -n "${_bp}" ]]; then
    _bp="$(_fotp "$(echo "${_bp}" | cut -d, -f1)" "${_SCthreshold}")${_bp}"
  else
    _bp="${__WARNING__} check for contributor diversity not run"
  fi

  echo "${_bp}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_pub_priv()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  jq -j '"Visibility is: ", .visibility, "<br/>Private is: ", .private' "${1}"
  return
}

_unrestricted()
{
  echo "Read-Only: manual<br/>Write: manual"
  return
}

_login_cred()
{
  echo "Manual"
  return
}

_license_name()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  jq -j '"License: ", .license.name, " SPDX_ID: ", .license.spdx_id|@html' "${1}"
  return
}

_license_risk()
{
  local _c
  local _p
  local _pi
  local _r

  _c="No restrictive license detected"
  # false positive check
  # shellcheck disable=2102
  [[ -v licenseChecks[restrictive] ]] && _c="Detected $(_fotp "${MYcheckScores[ProjectRestrictiveLicense]}" "${MYcheckThresholds[ProjectRestrictiveLicense]}" gt)${MYcheckScores[ProjectRestrictiveLicense]} restrictive license(s) being: $(echo "${licenseChecks[restrictive]}"| tr ',' '\n' | sort | uniq | tr  '\n' ',' | sed 's/,$//g;s/,/, /g'). "

  # false positive check ${__WARNING__}
  # shellcheck disable=2102
  [[ -v licenseChecks[undetermined] ]] && _c="${_c}<br/>Found ${__WARNING__}$(( $(echo "${licenseChecks[undetermined]}" | tr -cd , | wc -c) + 1)) license(s) yet to be determined suitable: ${licenseChecks[undetermined]//,/, }. "

  _p="$(jq -r '.[]|select(.riskType=="licenseRisk")|.title' "${1}" | sed 's/Commercial license risk detected in .*$/Commercial license risk detected/g' | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g')"
  [[ -z "${_p}" ]] && _p="Detected no product or dependent license(s) detected "

  _pi="($(jq -r '.[]|select(.riskType=="licenseRisk")|.impact' "${1}" | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g'))"
  [[ $_pi == "()" ]] && _pi="no impacts"
  _r="${_p} and ${_pi} potentially reported from dependencies"
  { [[ "${_p}" =~ .*critical*. ]] || [[ "${_p}" =~ .*high*. ]]; } && _r="${__REDFLAG__}${_p}"
  #{ [[ "${_p}" == *critical\;* ]] || [[ "${_p}" == *high\;* ]]; } && _r="${__REDFLAG__}${_p}"

  echo "${_c}<p/>Phylum reports ($(_fotp "${PHYcheckScores[license]}" "${PHYcheckThresholds[license]}")${PHYcheckScores[license]}): ${_r}"

  return
}

_eng_risk()
{
  local _c
  local _r

  _c="$(jq -r '.[]|select(.riskType=="engineeringRisk")|.title' "${1}" | cut -d\  -f2- | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g')"
  [[ -z "${_c}" ]] && echo "No product or dependent engineering risk(s) detected" && return

  _c="Detected in component(s): ${_c} ($(jq -r '.[]|select(.riskType=="engineeringRisk")|.impact' "${1}" | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g'))"
  _r="${_c} detected including dependencies"
  { [[ "${_c}" =~ .*critical*. ]] || [[ "${_c}" =~ .*high*. ]]; } && _r="${__REDFLAG__}${_c}"
  #{ [[ "${_c}" == *critical\;* ]] || [[ "${_c}" == *high\;* ]]; } && _r="${__REDFLAG__}${_c}"

  echo "${_r}"

  return
}

_mal_code()
{
  local _c
  local _r

  _c="$(jq -r '.[]|select(.riskType=="maliciousCodeRisk")|.title|@html' "${1}" | cut -d\  -f2- | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g')"
  [[ -z "${_c}" ]] && echo "No product or dependent malicious code(s) detected" && return

  _c="Detected in component(s): ${_c} ($(jq -r '.[]|select(.riskType=="maliciousCodeRisk")|.impact' "${1}" | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g'))"
  _r="${_c} detected including dependencies"
  { [[ "${_c}" =~ .*critical*. ]] || [[ "${_c}" =~ .*high*. ]]; } && _r="${__REDFLAG__}${_c}"
  #{ [[ "${_c}" == *critical\;* ]] || [[ "${_c}" == *high\;* ]]; } && _r="${__REDFLAG__}${_c}"

  echo "${_r}"

  return
}

_vul_check()
{
  local _sc
  local _sr
  local _c
  local _r

  #
  # see what OSSF scorecard reports
  #_sc="$(jq -r '.checks[]|select(.name=="Vulnerabilities")|.details|length' "${2}")"
  #_sr="${_sc} vul(s) found in the primary component"
  #[[ "${_sc}" -le "0" ]] && _sr="No vuls found in primary component"

  if [ -s "${2}" ]; then
    _sc="$(jq -r '.checks[]|select(.name=="Vulnerabilities")|[.score,"/10 as ",.reason]|@csv' "${2}")"
    _sc="$(_fotp "$(echo "${_sc}" | cut -d, -f1)" "${_SCthreshold}")${_sc}"
  else
    _sc="no insight from scorecard"
  fi

  #
  # see what Phylum scorecard reports
  #_c="$(jq -r 'def mywr: ("<a href=https://google.com>" + . + "</a>"); .issues[]|select(.riskType=="vulnerabilities")|.impact' "${1}" | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g')"
  _c="$(jq -r '.[]|select(.riskType=="vulnerabilities")|.impact' "${1}" | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g')"
  _r=" and detected vuls from other dependencies identified potentially: ${_c}"

  _crits="$(jq -r '.[]|select(.riskType=="vulnerabilities" and .impact=="critical")|.tag' "${1}" |sort|uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g;s/ [CHMI]V/ /g')"
  _w=" with criticals being ${__REDFLAG__}${_crits}"

  [[ -z "${_c}" ]] && _r=" and no dependent vul(s) detected"
  [[ -z "${_crits}" ]] && _w=""

  echo "${_sc}${_r}${_w}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_dep_pinned()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local _dpin

  _dpin="$(jq -j -r '.checks[]|select(.name=="Pinned-Dependencies")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  _dpin="$(_fotp "$(echo "${_dpin}" | cut -d, -f1)" "${_SCthreshold}")${_dpin}"
  echo "${_dpin}" | tr -d '\n' | sed 's/\n//g;s/\r//g;s/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_dep_up2date()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _sc="$(jq -r '.checks[]|select(.name=="Dependency-Update-Tool")|.score' "${1}")"
  _sr="$(jq -r '.checks[]|select(.name=="Dependency-Update-Tool")|.reason' "${1}")"

  case "${_sc}" in
    -1)
      _sc="undetermined"
      _sr="could not perform check"
      ;;
    0)
      _sc="${__REDFLAG__}No"
      ;;
    10)
      _sc="Yes"
      ;;
    *)
      _sc="Somewhat"
      ;;
  esac

  # shellcheck disable=2046
  echo $(
    echo "${_sc} with ${_sr}"
    echo "; investigate if any dependencies apply to more than the pipeline";
  ) | sed 's/"//g;s/ ,/ /g'
  return
}

_project_dep()
{
  local _pat
  local _f
  local _mod
  local _found
  local _c

  _pat='^[1],'
  _f="${2}"
  #
  # -i is safe here as we're grep'ing digits
  #
  _mod="-i"
  _found=',100'
  [ "${1}" == "--subs" ] && _pat='^[01],' && _f="${3}" && _mod='-v' && _found=',200'

  {
    echo -n "Total found: ";
    # shellcheck disable=2126
    _c="$(grep ${_mod} -E "(${_pat})" "${_f}" | wc -l)";
    echo "$(_fotp --warnFlag "${_c}" "0")${_c}"
    echo -n ", dependencies pulled: ";
    # shellcheck disable=2126
    _c="$(grep ${_mod} -E "(${_pat})" "${_f}" | grep "${_found}" | wc -l)";
    echo "$(_fotp --warnFlag "${_c}" "0")${_c}"
    echo -n ", dependencies unknown: ";
    # shellcheck disable=2126
    _c="$(grep ${_mod} -E "(${_pat})" "${_f}" | grep ",404" | wc -l)";
    echo "$(_fotp --warnFlag "${_c}" "1" "ge")${_c}"
  }

  return
}

_code_scanners()
{
  local _t
  local _v
  local _q

  _hcmsg="with no insight from hipcheck"
  if [ -s "${2}" ]; then
    _v="$(jq -r '..|select(.analysis?=="Fuzz")|[.value]|@csv' "${2}")"
    _v="${_v//,*/}"
    _q=""
    [[ -n "${_v}" ]] && {
      [ "${_v}" = "false" ] && _q="${__REDFLAG__}not "
      _hcmsg="with repository ${_q}receiving regular fuzz testing";
    }
  fi

  if [ -s "${1}" ]; then
    _fuzz="$(jq -r '.checks[]|select(.name=="Fuzzing")|[.score,"/10 as ",.reason]|@csv' "${1}")"
    _fuzz="$(_fotp "$(echo "${_fuzz}" | cut -d, -f1)" "${_SCthreshold}")${_fuzz}"
    _sast="$(jq -r '.checks[]|select(.name=="SAST")|[.score,"/10 as ",.reason]|@csv' "${1}")"
    _sast="$(_fotp "$(echo "${_sast}" | cut -d, -f1)" "${_SCthreshold}")${_sast}"
    _ci="$(jq -r '.checks[]|select(.name=="CI-Tests")|[.score,"/10 as ",.reason]|@csv' "${1}")"
    _ci="$(_fotp "$(echo "${_ci}" | cut -d, -f1)" "${_SCthreshold}")${_ci}"
    _msg="${_fuzz} ${_hcmsg}<br/>${_sast}, and <br/>${_ci}";
  else
    _msg="no insight from scorecard and ${_hcmsg}"
  fi

  echo "${_msg}" | tr -d '\n' | sed 's/\n//g;s/\r//g;s/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_repo_protections()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return
  _bp="$(jq -r '.checks[]|select(.name=="Branch-Protection")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  _bp="$(_fotp "$(echo "${_bp}" | cut -d, -f1)" "${_SCthreshold}")${_bp}"
  _dw="$(jq -r '.checks[]|select(.name=="Dangerous-Workflow")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  _dw="$(_fotp "$(echo "${_dw}" | cut -d, -f1)" "${_SCthreshold}")${_dw}"
  _tp="$(jq -r '.checks[]|select(.name=="Token-Permissions")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  _tp="$(_fotp "$(echo "${_tp}" | cut -d, -f1)" "${_SCthreshold}")${_tp}"
  _wh="$(jq -r '.checks[]|select(.name=="Webhooks")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  if [[ -n "${_wh}" ]]; then
    _wh="$(_fotp "$(echo "${_wh}" | cut -d, -f1)" "${_SCthreshold}")${_wh}"
  else
    _wh="${__WARNING__} check that webhooks is configured supporting secrets not run"
  fi

  echo "${_bp}<br/>${_dw}<br/>${_tp}, and<br/>${_wh}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_peer_reviews()
{
  local _t
  local _v
  local _q
  local _verb

  if [ -s "${2}" ]; then
    _v="$(jq -r 'def pct: .*10000.0|round/100; ..|select(.analysis?=="Review")|[(.value|pct),(.threshold|pct)]|@csv' "${2}")"
    _t="${_v//*,/}"
    _v="${_v//,*/}"
    _q="under"
    _verb="receiving"
    [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over" && _verb="lacking"

    _v2="$(jq -r 'def pct: .*10000.0|round/100; ..|select(.analysis?=="Identity")|[(.value|pct),(.threshold|pct)]|@csv' "${2}")"
    _t2="${_v2//*,/}"
    _v2="${_v2//,*/}"
    _q2="under"
    _verb2="not"
    [[ $(echo "${_v2} > ${_t2}" | bc -l) -eq 1 ]] && _q2="${__REDFLAG__}over" && _verb2="too"
    _hcmsg="$(
      echo "with change requests often ${_verb} approving review prior to merge with ${_v}% ${_q} the ${_t}% threshold"
      echo "and commits ${_verb2} often applied by the author with ${_v2}% ${_q2} the ${_t2}% threshold"
    )"
  else
    _hcmsg="with no insight from hipcheck"
  fi

  if [ -s "${1}" ]; then
    _v3="$(jq -r '.checks[]|select(.name=="Code-Review")|.score' "${1}")"
    [[ $(echo "${_v3} <= (10/3)" | bc -l) -eq 1 ]] && _v3="${__REDFLAG__}${_v3}"
    _scmsg="$(
      echo "Count pending; and activity is ${_v3}";
      jq -r '.checks[]|select(.name=="Code-Review")|["as ",.reason]|@csv' "${1}"
    )"
  else
    _scmsg="Count pending; and no insight from scorecard"
  fi

  # shellcheck disable=2046
  echo $(
    echo "${_scmsg}";
    echo "${_hcmsg}";
  ) | sed 's/"//g;s/ ,/ /g'
  return
}

_large_commits()
{
  local _t
  local _v
  local _q
  local _qq

  if [ -s "${2}" ]; then
    _v="$(jq -r '..|select(.analysis?=="Churn")|[.value,.threshold]|@csv' "${2}")"
    _t="${_v//*,/}"
    _v="${_v//,*/}"
    if [ -z "${_v}" ]; then
      _hcmsg="$(jq -r '..|select(.analysis?=="Churn")|[.error.msg," as ",.error.source.msg]|@csv' "${2}" | sed 's/\"//g;s/,//g')"
      _hcmsg="${__WARNING__}${_hcmsg^}"
    else
      _q="under or at"
      _qq=" some "
      [[ $(echo "${_v} <= 0" | bc -l) -eq 1 ]] && _qq=" no "
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _qq=" " && _q="${__REDFLAG__}over"
      _hcmsg="Detected${_qq}unusually large commits being $(_fppp "auto" "${_v}") found ${_q} the ${_t} permitted threshold"
    fi
  else
    _hcmsg="with no insight from hipcheck"
  fi

  echo "${_hcmsg}"
  return
}

_obscure_code()
{
  local _t
  local _v
  local _q
  local _qq

  if [ -s "${2}" ]; then
    _v="$(jq -r '..|select(.analysis?=="Entropy")|[.value,.threshold]|@csv' "${2}")"
    _t="${_v//*,/}"
    _v="${_v//,*/}"
    if [ -z "${_v}" ]; then
      _hcmsg="$(jq -r '..|select(.analysis?=="Entropy")|[.error.msg," as ",.error.source.msg]|@csv' "${2}" | sed 's/\"//g;s/,//g')"
      _hcmsg="${__WARNING__}${_hcmsg^}"
    else
      _q="under or at"
      _qq=" some "
      [[ $(echo "${_v} <= 0" | bc -l) -eq 1 ]] && _qq=" no "
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _qq=" " && _q="${__REDFLAG__}over"
      _hcmsg="Detected${_qq}unusual-looking commits being $(_fppp "auto" "${_v}") found ${_q} the ${_t} permitted threshold"
    fi
  else
    _hcmsg="with no insight from hipcheck"
  fi

  echo "${_hcmsg}"
  return
}

_binary_artifacts()
{
  local _t
  local _v
  local _q

  # TODO: change all tests for all scorecards to
  #       check for _v before check with bc(1)
  #       as done here. Look for
  #       'no insight from hipcheck'
  #
  _hcmsg="with no insight from hipcheck"
  if [ -s "${2}" ]; then
    _v="$(jq -r '..|select(.analysis?=="Binary")|[.value,.threshold]|@csv' "${2}")"
    _t="${_v//*,/}"
    _v="${_v//,*/}"
    _q="under or at"
    [[ -n "${_v}" ]] && {
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over";
      _hcmsg="with binaries potentially containing code being ${_v} found ${_q} the ${_t} permitted threshold";
    }
  fi

  if [ -s "${1}" ]; then
    _scmsg="$(jq -r '.checks[]|select(.name=="Binary-Artifacts")|[.score,"/10 as ",.reason]|@csv' "${1}")"
    _scmsg="$(_fotp "$(echo "${_scmsg}" | cut -d, -f1)" "${_SCthreshold}")${_scmsg}"
  else
    _scmsg="no insight from scorecard"
  fi
  # shellcheck disable=2046
  echo $(
    echo "${_scmsg}"
    echo "${_hcmsg}"
  ) | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_typo_risk()
{
  local _t
  local _v
  local _q

  if [ -s "${3}" ]; then
    _v="$(jq -r '..|select(.analysis?=="Typo")|[.value,.threshold]|@csv' "${3}")"
    _t="${_v//*,/}"
    _v="${_v//,*/}"
    if [ -z "${_v}" ]; then
      _hcmsg="$(jq -r '..|select(.analysis?=="Typo")|[.error.msg," as ",.error.source.msg]|@csv' "${3}" | sed 's/\"//g;s/,//g')"
      _hcmsg="${__WARNING__}${_hcmsg^}"
    else
      _q="under or at"
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over"
      _hcmsg="Detected potential typosquatting risks being ${_v} found ${_q} the ${_t} permitted threshold"
    fi
  else
    _hcmsg="with no insight from hipcheck"
  fi

  echo "${_hcmsg}"
  return
}

_problem_reporting()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _scmsg="$(jq -r '[.has_issues,"with", .open_issues,"open issues"]|@tsv' "${1}" | sed 's/"//g;s/\t/ /g;s/TRUE/Yes/gi')"
  if ! echo "${_scmsg}" | grep -q -E "(^Yes)"; then _scmsg="${__REDFLAG__}${_scmsg}"; fi

  echo "${_scmsg//false/None}"
  return
}

_vulsec_reporting()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _vuls="$(jq -r '.checks[]|select(.name=="Security-Policy")|[.score,"/10 as ",.reason]|@csv' "${1}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;')"
  _vuls="$(_fotp "$(echo "${_vuls}" | cut -d/ -f1)" "${_SCthreshold}")${_vuls}"
  echo "${_vuls}"
  return
}

_signed_releases()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _sign="$(jq -j -r '.checks[]|select(.name=="Signed-Releases")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  _sign="$(_fotp "$(echo "${_sign}" | cut -d, -f1)" "${_SCthreshold}")${_sign}"
  _pkg="$(jq -j -r '.checks[]|select(.name=="Packaging")|[.score,"/10 as ",.reason]|@csv' "${1}")"
  _pkg="$(_fotp "$(echo "${_pkg}" | cut -d, -f1)" "${_SCthreshold}")${_pkg}"
  echo -n "${_sign}, and<br/>${_pkg}; investigate if any such signing(s) are crytopgraphic" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_badactors()
{
  local _t
  local _v
  local _q

  if ${__ghSKIP}; then
    _hcmsg=" (and contributor's affiliations unknown as project is not on GitHub)"
    _v=0
  else #{
    _hcmsg="with no insight from hipcheck"
    if [ -s "${2}" ]; then
      _v="$(jq -r '..|select(.analysis?=="Affiliation")|[.value,.threshold]|@csv' "${2}")"
      _t="${_v//*,/}"
      _v="${_v//,*/}"
      _q="at or under"
      [[ -n "${_v}" ]] && {
        [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over"
        _hcmsg="with contributors affiliations being ${_v} found ${_q} the ${_t} permitted threshold";
      }
    fi
  fi #}

  local _score
  local _phmsg
  if [ -s "${1}" ]; then
    _score="$( jq -r '.riskScores.author' "${1}" )"
    #
    # account for legacy and new Phylum json format
    # assumes compute_p4_scores called before _badactors
    [[ "${_score,,}" == "null" ]] && _score="${PHYcheckScores[author]}"
    _phmsg="No, none reported"
    [[ $(echo "${_score}" "<" "1.00" | bc -l) -eq 1 ]] && _phmsg="${__REDFLAG__}Yes, something reported, investigate"
  else
    _phmsg="no insight from Phylum"
  fi

  # shellcheck disable=2046
  echo $(
    echo "${_phmsg}"
    echo "${_hcmsg}"
  ) | sed 's/ ,/ /g;s/"//g'
  return
}

_thisRuntime()
{
  local _lf

  _lf="${1}"

  echo $(( ($(date +%s)-$(head -1 "${_lf}")) / 60 ))
  return
}

_totalRuntime()
{
  local _seconds
  local _count
  local _s
  local _f

  _f="$(mktemp)"

  for f in ${1} logs/${1}
  do
    [[ ! -f "${f}" ]] && continue;
    _s=$(head -1 "${f}"|grep -E '^[[:digit:]]');
    [[ -z "${_s}" ]] && continue;
    echo $(( $(stat --printf=%Y "${f}") - _s )) >> "${_f}"
  done

  _count="$(wc -l < "${_f}")"
  _seconds="$(awk '{s+=$1} END {printf "%.0f", s}' < "${_f}")"

  rm -f "${_f}"
  echo "$(( _seconds / 60 )) minute(s) over ${_count} run(s)"
  return
}

#
# customized digger to scrape a site looking for
# and URL/URI pointing to GitHub
# (handcrafted--needs care and feeding-sorry)
#
_dig4repo()
{
  _ret="unknown"

  #
  # if github, return early
  # TODO: check code of all instances of HTTPS: in this code (3 places)
  #       discovered on instance where phylum
  #       set a github repoUrl to :owner:/:repo:.git
  #       that .git at the end makes GH API, Scorecard
  #       and maybe hipcheck sick - here is where to
  #       strip it.
  #
  [[ "${1}" =~ ^github ]] && echo "${1}" && return 0

  case "${1}" in
    google.golang.org/*)
      _say "a scrapping repo" "${1}"
      _r=$(curl -L --silent --request GET --url "${1}" -o - | grep -E -i -A 10 "(repository)" | grep -E -i  "([[:space:]]github)")
      ;;
    golang.org/*|go.opentelemetry.io/*|go.elastic.co/*|cloud.google.com/go/*|go.uber.org/*|gotest.tools/*|go.opencensus.io)
      _say "b scrapping repo" "${1}"
      _u=$(curl -L --silent --request GET --url "${1}" -o - | grep -E href= | cut -d\" -f2)
      _r=$(curl -L --silent --request GET --url "${_u}" -o - |grep -E -A 3 Repository |grep -E noopener | cut -d\" -f2)
      ;;
    go.mozilla.org/*)
      _say "c scrapping repo" "${1}"
      _r=$(curl -L --silent --request GET --url "${1}" -o - | grep -E href= | grep source | cut -d\" -f2)
      ;;
    gopkg.in/*)
      _say "d scrapping repo" "${1}"
      _r=$(curl -L --silent --request GET --url "${1}" -o - | grep btn | grep github | cut -d\" -f4)
      ;;
    gocloud.dev)
      _say "e scrapping repo" "${1}"
      _r=$(curl -L --silent --request GET --url "${1}" -o - | grep -E "go-source" | cut -d\" -f4 | cut -d\  -f2)
      ;;
    *) _r=""
      _say "unknown repo pattern" "${1}"
      ;;
  esac

  [ -n "${_r}" ] && _ret="${_r}"

  echo "${_ret}"
  return
}

readonly _phy_pkg_api_retry_count=3
pull_phyPackage()
{ 
  local _phy_pkg=${1}
  local _outfile=${2}
  readonly _phy_pkg
  readonly _outfile
  local _retry=1
  
  #
  # do until a success or break after retries
  #
  while :; #{
  do
    #
    # return on success and the API did not throw expected bad code
    #
    if curl --silent --request GET \
          --url "https://api.phylum.io/api/v0/data/packages/${_phy_pkg}" \
          --header 'accept: application/json' \
          --header "authorization: Bearer $(phylum auth token -qq --bearer 2>>/tmp/curllogs)" \
          -o "${_outfile}" &&
       ! grep -q -E "(\"code\":[[:space:]](40?|500))" "${_outfile}"; then
      return 0
    fi
    #
    # if it is a 404 - don't bother retrying
    #
    if grep -q -E "(\"code\":[[:space:]](404))" "${_outfile}" 2>/dev/null; then
      return 1
    else
      [ $((_phy_pkg_api_retry_count-_retry)) -le 0 ] &&
        _warn "curl exceeded retry count for ${_phy_pkg}" && break
      _retry=$((_retry+1))
      _say "curl failed: penalty sleep of 3 $(phylum auth status 2>/dev/null 1>&2; echo ${?})" && sleep 3
    fi
  done #}
  
  #
  # default return fail
  return 1
} 

# Phylum API mangling
#
makePuri()
{
  local _c
  local _p

  _c="${1}"
  # golang:cloud.google.com/go:v0.94.0
  # golang/cloud.google.com%2Fgo/v0.94.0
  #
  # maven:com.google.guava:guava:30.1.1-jre
  # maven/com.google.guava%3Aguava/30.1.1-jre
  #
  # npm:@babel/highlight:^7.18.6
  # npm/%40babel%2Fhighlight/7.18.6
  #
  # assume golang (seems to be a common pattern substitution)
  #
  _p="${_c////%2F}";
  _p="${_p//://}";
  [[ "${_c}" =~ ^maven ]] && _p="$(echo "$_c"| awk -F':' '{print $1 "/" $2 "%3A" $3 "/" $4}')"
  #
  # there are some strange package names in npm id, especially for
  # version numbers - i've see https addresses, less-than, greater-than
  # signs which if used manually with the human api.phylum website
  # don't event work: this is a question/issue for phylum.io
  #
  [[ "${_c}" =~ ^npm ]] && _p="${_p//@/%40}" && _p="${_p//^/}" && _p="${_p//\~/}"
  echo -n "${_p}"
  return
}

#
# this digger works off primary dependencies
# from a phylum analysized project
#
_dig4subdep()
{
  #
  # this is recursive (but not parallel safe)
  #
  local _lev
  local _c
  local _ftoupdate
  local _dep
  local _depout
  local _pkg
  local _l
  local _rc
  local _d

  _lev="${1}"
  _c="${2}"
  _ftoupdate="${3}"
  readonly _lev
  readonly _ftoupdate
  readonly _c
 
  #
  # find all reasons to return to avoid infinite recursion
  #

  ${blockNetwork} && _warn "Offline mode, traversing sub component dependencies, skipped" && return 0

  # don't dig from 0, already for the primary (level 1) deps
  #
  [ "${_lev}" -eq 0 ] && _say "reached limit imposed at level ${_lev} returning..." && return
  #
  # TODO: fix/understand npm dependencies, this algorithm seemingly
  #       goes on forever - just stick to two levels until this is
  #       undertstood
  [[ "${_c}" =~ ^npm ]] && [ "${_lev}" -eq 2 ] && _warn "npm limit: found level ${_lev} skipping ${_c} returning..." && return


  # form pkg name, _c, into for needed by
  # phylum.io's API (_pkg) and the naming
  # convention for the subdependent cache
  #
  _pkg="$(makePuri "${_c}")"
  _dep="subdeps.d/$(mkdepdir "${_c}")"
  _depout="${_dep}/$(basename "${_dep}")"

  # start digging on this tree

   _say "-n" "."

  # have we been here before (circular, often deep, dependencies)
  # verbose symbol
  #   ^: is were returning from a completed visit (mostly seen)
  #   %: in the middle of a previous visit (rarely seen)
  #      
  [ -f "${_depout}_deps.json.visited" ] && _say "-n" "^" && return
  [ -f "${_depout}_deps.json.visited.err" ] && _say "-n" "^" && return
  [ -f "${_depout}_deps.json.visiting" ] && _say "-n" "%" && return

  mkdir -p "${_dep}"

  { ${BFLAGS[subdeps]} || ${force_rebuild}; } &&
    cp /dev/null "${_depout}_deps.json"

  # has the project this product represents already been pulled
  #
  # TODO: when curl fails with unauthorized a few things
  #       need to occur, retry (like on Unauthorized)
  #       and if the error cannot be overcome (weak try)
  #       then wack the visited/visiting files as there
  #       would be a need to return to the dependendencies
  #       and wack the _deps.json as it will contain the
  #       error message from phylum and not the results
  #
  [ ! -s "${_depout}_deps.json" ] &&
    _say -n "pulling ${_c} dependencies..." &&
    if ! pull_phyPackage "${_pkg}" "${_depout}_deps.json"; then
      [ ! -s "${_depout}_deps.json" ] &&
        _warn "curl failed for ${_c}"
      [ -s "${_depout}_deps.json" ] &&
        mv "${_depout}_deps.json" "${_depout}_deps.json.err" &&
        _warn "pull failed for ${_c}"

      touch "${_depout}_deps.json.visited.err"
      if ! grep -q --fixed-strings ",${_c}," "${_ftoupdate}"; then echo "${_lev},${_c},${_c},${_c},404" >> "${_ftoupdate}"; fi
      _say "-n" "&" && return
    fi;

  [ ! -s "${_depout}_deps.json" ] &&
    _fatal "${_depout}_deps.json is missing or empty"

  _patchIfNeeded "${_depout}_deps.json"

  touch "${_depout}_deps.json.visiting"

  #
  # TODO: recording here is really knowing if the component
  #       exists as it is after the dependency pull
  #
  _r="$(jq -r '.repoUrl' "${_depout}_deps.json")"
  [[ -z "${_r}" ]] && _r="unknown"
  # if (! grep -q ${id} /etc/passwd) && (! grep ${id} /etc/group); then echo not there; fi
  if ! grep -q --fixed-strings ",${_c}," "${_ftoupdate}"; then echo "${_lev},${_c},${_r},${_r},200" >> "${_ftoupdate}"; fi

  jq -r '.dependencies[]|.id' "${_depout}_deps.json" 2>/dev/null | \
    sort | \
    while :; do #{
      read -r _d
      if [ -z "${_d}" ]; then
        break;
      fi
      #
      # TODO: find/dig4repo for the 3rd arg of that file to update
      #
      _l=$((_lev+1))
      #
      # record dependency (parent/child) relationship
      #
      echo "#s ${_dep}" >> "${__tmp_dep_graph}" && echo "\"${_c}\" -> \"${_d}\";" >> "${__tmp_dep_graph}";
      _dig4subdep "${_l}" "${_d}" "${_ftoupdate}"
    done #}

  touch "${_depout}_deps.json.visited"
  rm -f "${_depout}_deps.json.visiting"
  _say "-n" "x"

  return
}

_phylum_prjId()
{
  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "${puri}" && return

  _prj="${1}" jq -r '
    .values[] | select(.name==env._prj) | 
      [ .name,.id ] | @csv' "${2}" | \
    cut -d, -f2 | sed 's/"//g'
}

#
# been here done that;
# only do _phylum_jobId automatically
# update once per session
#
_phylum_jobId_BHDT="false"

_phylum_jobId()
{
  local _job
  local _jobFile
  local _verb

  ${_phylum_jobId_BHDT} && jq -r '[.latestJobId,.updatedAt]|@csv' "${2}" | sed 's/"//g' && return

  #
  # do the rest of this if first time thru
  #
  # TODO: work this as used now this occurs in a
  #       subprocess and is not promoted to the parent
  #       so for now, the parent may also set this flag
  #
  _phylum_jobId_BHDT="true"
  _verb="has changed"

  _job=$(jq -r ".latestJobId" "${2}")

  [[ -s "${1}_job_${_job}.json" ]] && { ${blockNetwork} || ${protectNoUpdate}; } && _warn "Skipping any update for ${_job} (remove -p or -O from command line)" && jq -r '[.latestJobId,.updatedAt]|@csv' "${2}" | sed 's/"//g' && return

  [[ ! -s "${1}_job_${_job}.json" ]] && ${blockNetwork} && _warn "Offline mode, no job analysis status available" && return 0

  #
  # if the analysis job file does not exist,
  # let's create a null file to start
  # otherwise leave intact (for now)
  #
  [[ ! -f "${1}_job_${_job}.json" ]] &&
    _say "initializing job file" &&
    _verb="has been cached" &&
    cp /dev/null "${1}_job_${_job}.json"

  _jobFile="$(mktemp -u -p .)"
  _walker_file="$(mktemp -u -p .)"

cat <<-'_JQWALKEREOF' > "${_walker_file}"
# Apply f to composite entities recursively, and to atoms
def walk(f):
  . as $in
  | if type == "object" then
      reduce keys[] as $key
        ( {}; . + { ($key):  ($in[$key] | walk(f)) } ) | f
  elif type == "array" then map( walk(f) ) | f
  else f
  end;
walk(if type == "array" then sort else . end)
_JQWALKEREOF

  #
  # get job file
  #
  curl --silent -X \
    'GET' \
    "https://api.phylum.io/api/v0/data/jobs/${_job}" \
    -H 'accept: application/json' \
    -H "Authorization: Bearer $(phylum auth token --bearer)" \
    -o "${_jobFile}"

  #
  # if diff from existing job file, backup and replace
  #
  if cmp -s <(jq -S -f "${_walker_file}" "${1}_job_${_job}.json") <(jq -S -f "${_walker_file}" "${_jobFile}"); then
    _say "${_job} ${1}_job_${_job}.json is unchanged";
  else
    #
    # oldjobs is only for debug purposes and possible inspection
    #
    mkdir -p oldjobs
    [[ -d oldjobs ]] && find  . -maxdepth 1 -name '*_job_*.json.*' -print0 | xargs -0 -I {} mv {} ./oldjobs/
    mv "${1}_job_${_job}.json" "oldjobs/${1}_job_${_job}.json.${RANDOM}";
    mv "${_jobFile}" "${1}_job_${_job}.json";
    _say "${_job} ${_verb} to ${1}_job_${_job}.json";
  fi

  rm -f "${_walker_file}"
  rm -f "${_jobFile}"

  jq -r '[.latestJobId,.updatedAt]|@csv' "${2}" | sed 's/"//g'
  return
}

_phylum_jobStatus()
{
 local _job

  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "" && return

 _job="$(_phylum_jobId "${1}" "${2}")"
 jq -r '.status' "${1}_job_${_job/,*/}.json"
 return
}

_phylum_jobReport()
{
  local _status
  local _jobUpdated

  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "Job Analysis N/A for Package URI (-U)" && return

  [[ ${1} == --readOnly ]] && _phylum_jobId_BHDT="true" && shift 1

  _jobUpdated="$(_phylum_jobId "${1}" "${2}")"

  _status="$(_phylum_jobStatus "${1}" "${2}")"

  [[ "${_status}" == "incomplete" ]] && _status="${__REDFLAG__}${_status}"

  echo "${_jobUpdated/,/ updated at } (${_status})"
}

#
# TODO: contact phylum and ask why v0 of the API changed
# the output - why was the API contract not held
# what is now "risk_type" was originally "riskType"
# this patches that for now (until phylum makes other
# changes
#
_patchIfNeeded()
{
  ! grep -q riskType "${1}" && \
      grep -q risk_type "${1}" && \
      _say "${1} patching risk_type to be riskType" && \
      sed --in-place=.risk_type 's/risk_type/riskType/g' "${1}"
}

#
# builds a CSV file with the pattern
# <level>,<component name>,<URL>
# where:
#  <level> is 1 or greater, 1 being primary, 2 being secondary, etc.
#  <component name> is the name assigned by phylum's API
#  <URL> is the URL from phylum's API or found by _dig4repo()
#
_phylum_dep_components()
{
  #
  # TODO: this cache should be at the top-level and
  #       not in the phylum project local working dir
  #
  # get the phylum project id from list of projects
  #
  local _apiMethod

  ${blockNetwork} && _warn "Offline mode, traversing component dependencies, skipped" && return 0

  _apiMethod="projects"
  _prjid=$(_phylum_prjId "${1}" "${2}")
  [[ "${puri}" == "${_prjid}" ]] && _apiMethod="packages" && _prjid="$(makePuri "${puri}")"

  [[ -z "${_prjid}" ]] && _fatal "phylum-api project ${1} not found."

  #
  # TODO: test and warn / error if _prjid cannot be
  #       found - this could be related to a bad
  #       name for the phylum project or a pagination
  #       limit
  _say "getting dependencies of ${1} and _prjid=${_prjid}"

  #########
  # pre-cache phylum project product dependencies
  _say -n "checking ${1} project product dependency caches..."

  ${component_dep_rebuild} || ${force_rebuild} &&
    _say -n "forced clearing PH project product dependency caches..." && rm -f "${3}"

  [ ! -f "${3}" ] &&
    _say -n "building Phylum project product dependencies caches..." &&
    (
      (
        curl --silent --request GET \
          --url "https://api.phylum.io/api/v0/data/${_apiMethod}/${_prjid}" \
          --header 'accept: application/json' \
          --header "authorization: Bearer $(phylum auth token --bearer)" \
          -o "${3}"
      ) ||
      (
        _fatal "phylum-api project product dependency pre-cache failed."
      )
    )

  [ ! -f "${3}" ] || [ ! -s "${3}" ] &&
    _fatal "${3} is missing or empty"

  _say "OK"

  [ "$(find "${3}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${3} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  _patchIfNeeded "${3}"

  _say "resetting ${4}" && cp /dev/null "${4}" && cp /dev/null "${__tmp_dep_graph}" && component_subdep_rebuild="true";

  _say "getting Phylum analysis job" && _phylum_jobStatus "${1}" "${3}";

  jq -r '.dependencies[]|.id,.repoUrl' "${3}" | \
    while :; do #{
      read -r _c
      read -r _r

      if [ -z "${_c}" ]; then
        break;
      fi

      _dep=$(echo "${_c}" | cut -d: -f2)
      _repo=$(_dig4repo "${_dep}")
      if [ "${_repo}" == "unknown" ]; then
        _r=${_r//https:\/\//}
        _r=${_r//http:\/\//}
        _repo=$(_dig4repo "${_r}")
      fi

      echo "${5},${_c},${_dep},${_repo},100" >> "${4}"
      # 5   : 1,
      # _c  : rubygems:parallel:1.22.1,
      # _dep: parallel,
      # repo: github.com/grosser/parallel/tree/v1.22.1,
      # code: 100
      #
      # 5   : 1,
      # _c  : rubygems:json:2.6.1,
      # _dep: json,
      # repo: github.com/flori/json,
      # code: 100
      echo "# ${_dep}" >> "${__tmp_dep_graph}" && echo "\"${1}\" -> \"${_c}\";" >> "${__tmp_dep_graph}";

    done #}

  return
}

_phylum_subdep_components()
{
  _prds=${1}
  _prjs=${2}

  readonly _prds

  (${force_rebuild} || ${component_subdep_rebuild} ) &&
    _say -n "clearing subdep project dependency caches..." && find . \( -name \*visited -o -name \*visited.err \) -delete

  #
  # TODO: this is not done yet, this output file
  # _dep_prjs.csv.subs is a mesh of the primary
  # found in _dep_prjs.csv
  # and newly discovered sub-dependencies and the
  # _dep_prjs.csv.subs does not **yet** have the
  # projects in them
  #
  # came across a "sick" '.id' specifically:
  # "id": "maven:com.github.joshelser:dropwizard-metrics-hadoop-metrics2-reporter:0.1.2\n    ",
  # for apache/hive, # which results in a bad read for this loop, hence the 'grep -v'
  # TODO: find a general way to clean these inputs from phylum
  #
  jq -r '.dependencies[]|.id' "${_prds}" | grep -v -E '(^[[:space:]].*$|^$)' | \
    sort | \
    while :; do #{
      read -r _c
      if [ -z "${_c}" ]; then
        break;
      fi
      #_dig4subdep "${_level}" "${_c}" "${_prjs}".subs
      _dig4subdep "${_level}" "${_c}" "${_prjs}"
    done #}

  # TODO: to rebuild/pass over all previously
  #       (sub) dependencies found, need to 
  #       iterate over "${__component_prjs}".subs
  #       this would revisit all prior subs found
  #       and pick up where prior passed failed
  #       to successfully pull deps. Starting from
  #       level 0 (${__component_prjs}) would 
  #       likely fail as the traveler could see
  #       the top level had already been visited
}

_build_digraph()
{
  cat <<-_DIGRAPHEOF > "${__component_dep_graph}"
digraph G {

    graph [ resolution=128, fontname=Arial, fontcolor=blue, fontsize=10, rankdir=LR ];
    node [ fontname=Arial, fontcolor=blue, fontsize=10];
    edge [ fontname=Helvetica, fontcolor=red, fontsize=10 ];
    $(cat "${1}")
}
_DIGRAPHEOF

  return 0
}

#
# TODO: add rotating private access tokens
#       as 5000 calls/hr is not enough
#       rotating keys should prevent sleep
#
# Intended to be called before using GitHub API
# to ensure the ratelimit is not exceeded which
# if exceeded would cause the use to fail
# if approaching the ratelimit, sleep until
# the limit is reset (usually an hour at most)
#
waitRateLimit()
{
  local _l
  _l="${1}";

  curl -s -u "notUsed:${GITHUB_AUTH_TOKEN}" \
    -I https://api.github.com/user/octocat >/tmp/scw_ratelimit.txt 2>&1
  local _c
  _c=$(grep ^x-ratelimit-remaining: /tmp/scw_ratelimit.txt|cut -d: -f2|tr -d '\r')

  #_say l: ${_l}, c: ${_c}
  if [ "${_c}" -le "${_l}" ]; then
    local _r
    local _s
    _r=$(grep ^x-ratelimit-reset: /tmp/scw_ratelimit.txt|cut -d: -f2|tr -d '\r')
    _s=$((_r-$(date +%s)))
    if [ ! ${_s} -lt 0 ]; then
      _warn "sleeping ${_s} seconds to due to GitHub ratelimiting, Sleeping..."
      sleep ${_s}
    fi
  fi
}

#
# runs ghapi to get project meta data
#
_run_ghmeta()
{
  _joutput="${3}/${2}_ghapi.json"

  [ -f "${_joutput}.skip" ] &&
    _warn "gh api skipping ${1}, del ${_joutput}.skip to undo" &&
    return

  { ${BFLAGS[meta]} || ${force_rebuild}; } &&
    cp /dev/null "${_joutput}"

  [ ! -s "${_joutput}" ] &&
    _say "running gh api on ${1} to ${_joutput}" && 
    waitRateLimit "${_lowerLimit}" &&
    #
    # follow redirects
    # TODO: determine if there are other
    #       places where this needs to be
    #
    curl --location --silent \
      -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
      -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${1}" \
      -o "${_joutput}"

  #
  # TODO: silence this warning on things like "tarball" (and there
  #       may be others) this is the opposite reason of retrying
  #       when there is an error (like "ratelimit")
  #
  [ -s "${_joutput}.err" ] &&
    _warn "gh api failed for ${1} see ${_joutput}.err for hints"

  [ ! -s "${_joutput}.err" ] &&
    rm -f "${_joutput}.err"

  [ ! -s "${_joutput}" ] &&
    _warn "gh api ${_joutput} is incomplete, consider rebuilding (-f)"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "gh api ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  return
}

_run_criticality_score()
{
  _joutput="${3}/${2}.cs.json"

  [ -f "${_joutput}.skip" ] &&
    _warn "criticality score skipping ${1}, del ${_joutput}.skip to undo" &&
    return

  { ${BFLAGS[crit]} || ${force_rebuild}; } &&
    cp /dev/null "${_joutput}"

  [ ! -s "${_joutput}" ] && {
    _say "running criticality score on ${1} to ${_joutput}";
    waitRateLimit "${_lowerLimit}";
    #
    #
    ${_OSSFCS} -log Warn -depsdev-disable --format json \
      "https://github.com/${1}" 2>"${_joutput}.err.${$}" >"${_joutput}";
    #
    # take out spurious WARN (due to disable above) and messages which cannot seem to be silenced
    #
    grep -v -E '(signal source is disabled|collector.go|main.go|proc.go|main.main|runtime.main|collector.New)' "${_joutput}.err.${$}" > "${_joutput}.err"
    rm -f "${_joutput}.err.${$}"
  }

  [ -s "${_joutput}.err" ] &&
    _warn "criticality score failed for ${1} see ${_joutput}.err for hints"

  [ ! -s "${_joutput}.err" ] &&
    rm -f "${_joutput}.err"

  [ ! -s "${_joutput}" ] &&
    _warn "criticality score ${_joutput} is incomplete, consider rebuilding (-f)"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "criticality score ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  return
}

#
# runs scorecard trying to make smart choices on errors
#
_run_scorecard()
{
  _joutput="${3}/${2}.sc.json"

  [ -f "${_joutput}.skip" ] &&
    _warn "scorecard skipping ${1}, del ${_joutput}.skip to undo" &&
    return

  { ${BFLAGS[scard]} || ${force_rebuild}; } &&
    cp /dev/null "${_joutput}"

  # sudo redirect is fine here (SC2024)
  # shellcheck disable=2024
  [ ! -s "${_joutput}" ] &&
    _prjurl="https://github.com/${1}" &&
    _say "running scorecard LIVE on ${_prjurl} to ${_joutput}" && 
    waitRateLimit "${_lowerLimit}" &&
    ${_sudo} docker run --rm \
      -e SCORECARD_V6=true \
      -e "GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN}" "${_OSSFSC}" \
      --format=json --show-details \
      --repo="${_prjurl}" > "${_joutput}" 2> "${_joutput}.err"

  #
  # TODO: silence this warning on things like "tarball" (and there
  #       may be others) this is the opposite reason of retrying
  #       when there is an error (like "ratelimit")
  #
  [ -s "${_joutput}.err" ] &&
    _warn "scorecard failed for ${1} see ${_joutput}.err for hints"

  [ ! -s "${_joutput}.err" ] &&
    rm -f "${_joutput}.err"

  [ ! -s "${_joutput}" ] &&
    _warn "scorecard ${_joutput} is incomplete, consider rebuilding (-f)"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "scorecard ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  return
}

#
# runs hipcheck trying to make smart choices on errors
#
# one trick here is that hipcheck is run twice
# first: get the json results
# second: get the human readable analysis
#
# the second results are then integrated into the json
# results as a base64 encoding for later decoding
# (see the rationale key/value pair in _summary_scores)
#
# TODO: find a way to improve this without running twice
# TODO: like scorecard look for opportunities to retry
#       inspect outputs for errors known
#       errors seen to date include:
#         Error failed to clone remote repository
#         thread 'main' panicked at
#       also .json files which are 0 bytes where txt 
#       have appeared to properly built
# TODO: run hipcheck using docker volumes to set
#       "approved/standard" config *.toml values
#       e.g.:
#       docker run -v /tmp/del_Orgs.toml:/app/config/Orgs.toml ...
#
_run_hipcheck()
{
  _prjurl="https://github.com/${1}"
  _joutput="${3}/${2}.hc.json"
  _toutput="${3}/${2}.hc.txt"

  [ -f "${_joutput}.skip" ] &&
    _warn "hipcheck skipping ${1}, del ${_joutput}.skip to undo" &&
    return

  { ${BFLAGS[hcheck]} || ${force_rebuild}; } &&
    cp /dev/null "${_joutput}"

  # sudo redirect is fine here (SC2024)
  # shellcheck disable=2024
  [ ! -s "${_joutput}" ] && 
    _say "running hipcheck on ${_prjurl} to ${_joutput}" && 
    waitRateLimit "${_lowerLimit}" &&
    ${_sudo} docker run --rm \
      -v "${_MITRHCconfig}:/app/config" \
      -v "${_MITRHCscripts}:/app/scripts" \
      -e "HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN}" "${_MITRHC}" \
      -q \
      check repo "${_prjurl}" > "${_toutput}" 2>&1 &&
      (
        grep -E risk\ rated "${_toutput}" >/dev/null ||
        (
          _warn "hipcheck ${_toutput} failed, see file for hints" &&
          _debug "RETURNING FROM HERE" &&
          return
        )
      ) &&
    waitRateLimit "${_lowerLimit}" &&
    ${_sudo} docker run --rm \
      -v "${_MITRHCconfig}:/app/config" \
      -v "${_MITRHCscripts}:/app/scripts" \
      -e "HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN}" "${_MITRHC}" \
      -j \
      -q \
      check repo "${_prjurl}" > "${_joutput}" &&
      ( # mangle the json output to include the rationale from txt file
        head -n -2 "${_joutput}" ; 
        b64=$(base64 -w 0 "${_toutput}") ; 
        echo '  },'; 
        echo -n '  "rationale": "' ; echo -n "${b64}"; 
        echo '"'; echo -n '}'
      ) > "${_joutput}.tmp" &&
      mv "${_joutput}.tmp" "${_joutput}" &&
      if jq -r '.' "${_joutput}" > /dev/null 2>&1; then rm "${_toutput}"; fi &&
      [ -s "${_toutput}" ] && _warn "json filter error, ${_toutput} not deleted"

  [ ! -s "${_joutput}" ] &&
    _warn "hipcheck ${_joutput} is incomplete, consider rebuilding (-f)" &&
    [ -s "${_toutput}" ] &&
    _warn "hipcheck ${_toutput} failed, see file for hints"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "hipcheck ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  return
}

_run_mychecks()
{
  local check
  local _r

  ${__ghSKIP} && _warn "Project is not on GitHub" && return

  _say "Running MY specific checks"

  for check in "${!MYcheckScores[@]}"
  do
    case "${check}" in
      UnfixedVulnerabilities)
        MYcheckScores["${check}"]="${__CHECKNOTIMPL__}"
        ;;
      ProjectForked)
        MYcheckScores["${check}"]="$(jq -rj '.fork' "${1}")"
        ;;
      ProblemReporting)
        MYcheckScores["${check}"]="$(jq -rj '.has_issues' "${1}")"
        ;;
      DepProjectsForked)
        #
        # TODO: pull all dep.d repos from GHAPI
        #       to set this correctly, perhaps
        #       deps.d/.../<name>_ghapi.json
        #
        MYcheckScores["${check}"]="${__CHECKNOTIMPL__}"
        ;;
      TertiaryProjectsForked)
        #
        # TODO: pull all subdep.d repos from GHAPI
        #       to set this correctly, perhaps
        #       subdeps.d/.../<name>_ghapi.json
        #
        MYcheckScores["${check}"]="${__CHECKNOTIMPL__}"
        ;;
      ProjectAbandoned)
        MYcheckScores["${check}"]="$(jq -r '.archived' "${1}")"
        ;;
      DepProjectsAbandoned)
        _say -n "Counting abandoned projects..."
        #
        # scorecard 5.0 changed the "reason" check for both
        #
        MYcheckScores["${check}"]="$(find ./deps.d/ -name \*sc.json -print0 | \
          xargs -0 grep -E '(repo is marked as archived|project is archived)' | cut -d: -f1|wc -l)"
        _say "abandoned projects counting done."
        ;;
      TertiaryProjectsAbandoned)
        #
        # TODO: add this after scorecard and hipcheck are run on
        # tertiary dependencies (subdep.d)
        #
        # are any of the tertiary dependencies abandoned (med)
        #_tarchived="$(find ./subdeps.d/ -name \*sc.json -print0 | \
        #  xargs -0 grep "repo is marked as archived" | cut -d: -f1|wc -l)"
        #
        MYcheckScores["${check}"]="${__CHECKNOTIMPL__}"
        ;;
      ProjectRestrictiveLicense)
        #
        # TODO: add rubric for assessing what is and is
        #       not a restrictive license
        #
        _count_licenses
        #
        # assume no restrictive licenses until give evidence
        MYcheckScores["${check}"]=0
        _r="$(_find_restrictive_licenses --all)"
        [[ -n "${_r}" ]] && licenseChecks[restrictive]="${_r}"
        # if unset don't try to count
        # false positive check
        # shellcheck disable=2102
        [[ -v licenseChecks[restrictive] ]] && 
          MYcheckScores["${check}"]=$(( $(echo "${licenseChecks[restrictive]}" | tr -cd , | wc -c) + 1))
        _r="$(_find_undetermined_licenses --all)"
        [[ -n "${_r}" ]] && licenseChecks[undetermined]="${_r}"
        ;;
      DepProjectsRestrictiveLicense)
        _count_licenses
        MYcheckScores["${check}"]="${__CHECKNOTIMPL__}"
        #MYcheckScores["${check}"]="$(_find_restrictive_licenses --primary)"
        ;;
      TertiaryProjectsRestrictiveLicense)
        _count_licenses
        MYcheckScores["${check}"]="${__CHECKNOTIMPL__}"
        #MYcheckScores["${check}"]="$(_find_restrictive_licenses --tertiary)"
        ;;
      *)
        ;;
    esac
  done

  _say "MY specific checks done"
  return
}

_count_licenses()
{
  local _f

  #
  # if array is set, been here, done that - just return
  #
  [[ -v foundLicenses[@] ]] && return

  _say -n "Counting licenses detected by GH API..."
  #
  # find all the GH API jsons which have license info
  # and grab the SPDX ID, then using sort/uniq -c 
  # echo back a count=license (sep'd by ':') of the 
  # number if times specific SPDX IDs are encountered
  #
  _f="$(find . -name \*_ghapi.json -print0 | \
      xargs -0 jq -r '.license.spdx_id' | \
      sort | uniq -c | sort | \
      sed 's/^[ \t]*//g;s/ /=/;s/$/:/' | \
      tr -d '\n'|sed 's/:$//')"

  #
  # TODO: determine if it is prudent at this point to set a
  #       dummy val in foundLicenses so the test above for set
  #       will be true so this find is not run more than once
  #       for this instance of the report (i.e, foundLicenses[dummy]=0)
  #
  [[ -z "${_f}" ]] && _warn "No license information found at all" && return

  #
  # now populate the associative array
  #
  while IFS="=" read -r _lc _ln;
  do
    foundLicenses["${_ln}"]="${_lc}"
  done < <(echo "${_f}" | tr ':' '\n')

  _say "license counting done."
  return
}

#
# returns a CSV list of restricted licences
#
_find_restrictive_licenses()
{
  local _frl

  [ ${#foundLicenses[@]} -le 0 ] && _count_licenses

  case "${1}" in
    --all) _frl=$(
             jq -r \
              --arg found "$(printf "%s " "${!foundLicenses[@]}"|sed 's/ $//')" \
             '
              . + { "__myfound__": $found|split(" ") } |
              . |
              .__myfound__ as $FN |
              .licenses[] |
              select((.spdxId==($FN[]) or .spdxIdDeprecated==($FN[]) )
                    and
                     (.properties.discloseSource == "true"
                      or
                      .properties.networkUseIsDistribution == "true")
                    ) | [ .spdxId ]
             ' "${_OSSSCIRlicenseDB}" | \
             jq -r --slurp 'unique|add|@csv' 2>/dev/null)
    ;;
    --project)
    ;;
    --primary)
    ;;
    --tertiary)
    ;;
  esac

  echo "${_frl//\"}"
  return
}

#
# returns a CSV list of undetermined licences
#
_find_undetermined_licenses()
{
  local _ful

  [ ${#foundLicenses[@]} -le 0 ] && _count_licenses

  case "${1}" in
    --all) _ful=$(
             jq -r --null-input \
               --arg known "$(jq -r \
                 '.licenses[].spdxId,.licenses[].spdxIdDeprecated|select(length>0)'\
                  "${_OSSSCIRlicenseDB}"|tr '\n' ' ')" \
               --arg found "$(printf "%s " "${!foundLicenses[@]}")" \
             '
              { } |
              . + { "__myknown__": $known|split(" ") } |
              . + { "__myfound__": $found|split(" ") } |
              .__myfound__ - .__myknown__ |
              @csv
             ')

    ;;
    --project)
    ;;
    --primary)
    ;;
    --tertiary)
    ;;
  esac

  echo "${_ful//\"}"
  return
}

__police_scorecards()
{
  local _scoreRunnerPID
  local _PIDtty
  local _containerTimeout
  local _containerPID
  local _containerCID
  local _politePolice

  _containerTimeout="${2}"
  _PIDtty="${3}"
  _politePolice=5

  #
  # TODO: fail to run it tty is "not a tty"
  #       just error/return 3

  #
  # want this for synchronization
  #
  read -r _scoreRunnerPID

  # likely unneccessary but harmless double check
  [[ "${_scoreRunnerPID}" != "${1}" ]] &&
    _warn "_scoreRunnerPID != ${1}" &&
    return 1

  _scoreRunnerPID="${1}"

  # want this though passed equals what was piped
  ! pgrep -a -t "${_PIDtty}" | grep -q "${_scoreRunnerPID}" && {
    _warn "no pid ${_scoreRunnerPID} on that tty ${_PIDtty}" &&
    return 2
  }

  # do this as long as our parent/grandparent is around (no zombies)
  while [[ -d /proc/${_scoreRunnerPID} ]]
  do
    # honor parent/grandparent job control (STOP|CONT)
    grep State "/proc/${_scoreRunnerPID}/status" |grep -q stopped && sleep "${_politePolice}" && _say "${_scoreRunnerPID} PAUSED" && continue

    # only track containers on the same tty as a parent/grandparent
    _containerPID=$(pgrep -a -t "${_PIDtty}" -f "docker run" | grep _TOKEN | awk '{ print $1 }')
    #_containerPID=$(ps -ef|grep -i docker\ run | grep _TOKEN | awk '{ print $2 }')
    [[ -z "${_containerPID}" ]] && sleep "${_politePolice}" && continue

    #
    # TODO: not sure if possible, grab the right container
    #       if this returns more than one running container
    #
    _containerCID="$(docker ps |grep -v STATUS |awk '{ print $1 }')"
    [[ -z "${_containerCID}" ]] && sleep "${_politePolice}" && continue

    _start="${EPOCHSECONDS}"

    _say "watching PID=${_containerPID} ($(tr '\0' ' ' <"/proc/${_containerPID}/cmdline" | grep -o -E '(scorecard|hipcheck)'|head -1)), CONTAINER=${_containerCID} on ${_PIDtty} not to exceed ${_containerTimeout} seconds"
    #
    # TODO: to be sure, track the PID not the ID
    #       as the PID is likely the truth here
    #       and less subject to disambiguation
    #
    #while [[ -n "${_containerCID}" ]]
    while [[ -n "${_containerPID}" ]]
    do
      [[ $(( EPOCHSECONDS - _start )) -ge _containerTimeout ]] &&
        _warn "killed ${_containerPID}/${_containerCID}: working on $(tr '\0' ' ' <"/proc/${_containerPID}/cmdline")" &&
        ${_sudo} docker kill "${_containerCID}"
      sleep "${_politePolice}"
      grep State "/proc/${_scoreRunnerPID}/status" |grep -q stopped && _say "${_scoreRunnerPID} PAUSED breaking" && break
      _containerPID=$(pgrep -a -t "${_PIDtty}" -f "docker run" | grep "${_containerPID}" | awk '{ print $1 }')
      #_containerCID="$(docker ps |grep -v STATUS |grep "${_containerCID}" |awk '{ print $1 }')"
      _say -n "."
    done
    _say ""
  done

  return 0
}

#
# name sez all, uses waitRateLimit to reduce
# errors at runtime, and will also retry a
# run if the run should fail (as sometimes
# seen with secondary ratelimiting and network
# hiccups
#
build_scorecards()
{
  local _seq
  local __policePID

  ${blockNetwork} && _warn "Offline mode, invocation of score tooling, skipped" && return 0

  _say "selecting only unique github project repos from ${2} from 0 up upto and including level \"${3}\" (see: -D to change)"

  _seq='^[0-9]+,'
  [[ ${3} != "all" ]] && _seq="^($(seq --separator='|' 0 "${3}")),"

  #
  # this synchronously launches a docker "watcher" policer
  # controlled by (-W)
  #
  [[ -n "${scoreTimeout}" ]] && {
    local _mytty;
    _mytty=$(tty);
    echo "${$}" | __police_scorecards "${$}" "${scoreTimeout}" "${_mytty/\/dev\/}" & 
    __policePID=$! ;

    _warn "Policing for potentially stalled scoring containers on ${_mytty/\/dev\/} (see: -W to change)" ;
  }

  grep -E "${_seq}" "${2}" \
    | cut -d, -f4 \
    | grep github \
    | sed  's^HTTPS://^^gi;s^\.git^^gi'  \
    | cut -d/ -f2,3 \
    | sort \
    | uniq \
    | while :; do #{
      read -r _OwnerRepo

      [ -z "${_OwnerRepo}" ] && break

      [ "${_OwnerRepo}" = "${__NULLGH__}" ] && continue

      _say -n "*"
      _localdepdir="deps.d/$(mkdepdir "${_OwnerRepo}")"
      mkdir -p "${_localdepdir}"

      #
      # GH API project metadata
      #
      _err="${_localdepdir}"/"$(basename "${_localdepdir}")"_ghapi.json.err
      rm -f "${_err}"
      _run_ghmeta "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}"
      grep -q -E -o '("message": "Not Found",)' "${_localdepdir}/$(basename "${_localdepdir}")_ghapi.json" && \
        _warn "gh api: ${_OwnerRepo} not found"

      #
      # OSSF criticality score
      #
      _err="${_localdepdir}"/"$(basename "${_localdepdir}")".cs.json.err
      rm -f "${_err}"
      _run_criticality_score "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}"
      [[ -s "${_err}" ]] && grep -q -E -o '("error": "repo failed:)' "${_err}" && \
        _warn "criticality score: ${_OwnerRepo} not found"

      #
      # scorecard do/while
      #
      local _retry="true"
      #
      # clear any err file
      # TODO: this rm for the err file is in the
      #       wrong place as it is not for sure
      #       _run_scorecard will actually do anything
      #
      _err="${_localdepdir}"/"$(basename "${_localdepdir}")".sc.json.err
      rm -f "${_err}"
      while :; do #{
        _run_scorecard "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}" 
        if ! grep -q -E -o "(repo unreachable|exceeded a secondary rate limit|TLS handshake timeout)" "${_err}" 2>/dev/null ; then
          break
        fi
        #
        # one retry due to one of the conditions above
        #
        ! ${_retry} && break
        _retry="false"
        grep -q -E -o "(exceeded a secondary rate limit)" "${_err}" 2>/dev/null && \
          _warn "Sleeping 5 min for secondary rate limit before retry" && sleep 300
        _say -n "R*"
        rm -f "$(basename "${_localdepdir}")"/"${_localdepdir}".sc.json
      done #}

      #
      # hipcheck (does not yet need a do/while)
      #
      #
      # clear any err file
      #
      _err="${_localdepdir}"/"$(basename "${_localdepdir}")".hc.json.err
      rm -f "${_err}"
      _say -n "_"
      local _retry="true"
      _run_hipcheck "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}" 
      _retry="false"
  done #}

  #
  # stop the policer if launched and still running and/or collect the zombie
  #
  [[ -n "${scoreTimeout}" ]] && {
   if [ ! -d "/proc/${__policePID}" ]; then
     wait ${__policePID}
   else
     kill ${__policePID}
     wait ${__policePID}
   fi;
    _say "done policing for potentially stalled scoring containers on pts/2";
  }

  _say ""

  return
}

#
# look for pattens in the built scorecard
# score card and warn if a built card
# does not match a known good pattern
#
_val_scorecard()
{
  _prjurl="https://github.com/${1}"
  _joutput="${3}/${2}.sc.json"

  [ -f "${_joutput}.skip" ] &&
    #_warn "scorecard skipping validation on ${1}, del ${_joutput}.skip to undo" &&
    return

  # the suggested rewrite of the grep -q would
  # make the test to hard to read
  # shellcheck disable=2143
  [ -s "${_joutput}" ] && 
    {
      [ "$(jq -r '.checks[]|[ .name,.score ] | @csv' "${_joutput}" | wc -l)" -lt 18 ] ||
      [ -n "$(jq -r '.checks[]|[ .name,.score ] | @csv' "${_joutput}" | grep -E -o "(,$)")" ];
    } &&
     _warn "scorecard ${_joutput} failed, consider rebuilding (-f)" &&
     jq -r '.checks[]|[ .name,.score ] | @csv' "${_joutput}" | wc -l &&
     jq -r '.checks[]|[ .name,.score ] | @csv' "${_joutput}" | grep -E "(,$)" &&
     echo /dev/null "${_joutput}"

  return
}

#
# look for pattens in the built hipcheck
# score card and warn if a built card
# does not match a known good pattern
#
_val_hipcheck()
{
  _prjurl="https://github.com/${1}"
  _joutput="${3}/${2}.hc.json"

  [ -f "${_joutput}.skip" ] &&
    #_warn "hipcheck skipping validation on ${1}, del ${_joutput}.skip to undo" &&
    return

  [ -s "${_joutput}" ] && 
    {
      [ "$(jq -r '.recommendation.kind' "${_joutput}")" == "null" ] || 
      [ "$(jq -r '.rationale' "${_joutput}")" == "null" ];
    } && 
    _warn "hipcheck ${_joutput} failed, consider rebuilding (-f)"

  return
}

#
# name sez all, simply iterates through
# the score cards and validates them as
# having expected content
#
validate_scorecards()
{
  local _seq
  _say "validating only unique github project repos from ${1} from 0 up upto and including level \"${2}\" (see: -D to change)"

  _seq='^[0-9]+,'
  [[ ${2} != "all" ]] && _seq="^($(seq --separator='|' 0 "${2}")),"

  grep -E "${_seq}" "${1}" \
    | cut -d, -f4 \
    | grep github\
    | sed  's^HTTPS://^^gi;s^\.git^^gi' \
    | cut -d/ -f2,3\
    | sort \
    | uniq \
    | while :; do #{
      read -r _OwnerRepo

      [ -z "${_OwnerRepo}" ] && break

      [ "${_OwnerRepo}" = "${__NULLGH__}" ] && continue

      _say -n "+"
      _localdepdir="deps.d/$(mkdepdir "${_OwnerRepo}")"
      mkdir -p "${_localdepdir}"

      _val_scorecard "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}" 
      _val_hipcheck "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}" 

    done #}

  _say ""
  return
}

#
# create a single CSV with all the score card
# results coalesced into a single CSV row per
# project
#
coalesce_scorecards()
{
  _say "selecting only github project repos on ${2}"
  _missingJson=0

  while :; do #{
      read -r _OwnerRepo
    
      [ -z "${_OwnerRepo}" ] && break

      [ "${_OwnerRepo}" = "${__NULLGH__}" ] && continue

      _say -n "."
      _localdepdir="deps.d/$(mkdepdir "${_OwnerRepo}")"
      #_localdepdir="deps.d/$(echo "${_OwnerRepo}" | sed 's^/^___^g')"

      _SCinput="${_localdepdir}/$(basename "${_localdepdir}").sc.json"
      _HCinput="${_localdepdir}/$(basename "${_localdepdir}").hc.json"

      [ ! -s "${_SCinput}" ] || [ ! -s "${_HCinput}" ] && _missingJson=$((_missingJson+1)) && continue

      # CSV header (do once)
      # 3 parts to coalesce
      # part 1, first column, Component name (first echo -n)
      # part 2, next 18 cols, from scorecard (second echo -n)
      # part 3, last 9 cols, from hipcheck (third echo -n)
      #
      # word splitting is necessary for sort to work properly
      # shellcheck disable=2046
      ${coalesce_header} && 
        (
          echo -n "Component," &&
          echo -n $(jq -r '.checks[]|[ .name,.score ] | @csv' "${_SCinput}" | sort | cut -d, -f1 | sed 's/^"//g;s/"$/,/g') | sed 's/, /,/g;s/,$//g' && echo -n "," &&
          echo -n $( (jq -r '.passing[]| [.analysis,.value ]|@csv' "${_HCinput}"; jq -r '.failing[]| [.analysis,.value ]|@csv' "${_HCinput}";  jq -r '.errored[]| [.analysis,"-1"]|@csv' "${_HCinput}") | sort | cut -d, -f1 | sed 's/^"//g;s/"$/,/g' | sed 's/, /,/g;s/,$//g') | sed 's/ /,/g' &&
          echo ""
        ) > "${3}" &&
        coalesce_header="false"

      # CSV row (the values)
      # 3 parts, same sources as the header
      # TODO: need to test for _SCinput or insert -1 placeholders
      # TODO: round analysis values to fewer digits
      #       jq chokes on def roundit: .*100.0|round/100.0; when
      #       a value is not a numbers (i.e., "false")
      #
      # word splitting is necessary for sort to work properly
      # shellcheck disable=2046
      (
        echo -n "$(basename "${_localdepdir}"),"
        echo -n $(jq -r '.checks[]|[ .name,.score ] | @csv' "${_SCinput}" | sort | cut -d, -f2 | sed 's/^"//g;s/"$/,/g') | sed 's/ /,/g;s/,$//g'
        echo -n ","
        if [ -s "${_HCinput}" ]; then
          echo -n $( (jq -r '.passing[]| [.analysis,.value ]|@csv' "${_HCinput}"; jq -r '.failing[]| [.analysis,.value ]|@csv' "${_HCinput}";  jq -r '.errored[]| [.analysis,"-1"]|@csv' "${_HCinput}") | sort | cut -d, -f2 | sed 's/^"//g;s/"$/,/g' | sed 's/, /,/g;s/,$//g') | sed 's/ /,/g'
        else
          echo -n "-1,-1,-1,-1,-1,-1,-1,-1,-1"
        fi
        echo ""
      ) >> "${3}"

  done < <(cut -d, -f4 "${2}" | grep github| sed  's^HTTPS://^^gi;s^\.git^^gi' | cut -d/ -f2,3| sort | uniq) #}

  _say ""
  [ "${_missingJson}" -gt "0" ] && _warn "coalesce_scorecards: counted ${_missingJson} missing project scorecard(s)"
  [ ! -s "${3}" ] && _warn "coalesce_scorecards: no scores from scorecard or hipcheck found." && cp /dev/null "${3}"
  return
}

#
# builds frequently referenced (json) data sources
# for a phylum project and its GitHub counterparts
# helps to reduce the GitHub rateLimit enforements
#
build_caches()
{
  ${blockNetwork} && _warn "Offline mode, cache updates, skipped" && return 0

  #########
  # pre-cache github site html which may have badge information
  _say -n "checking GH html..."

  if ${BFLAGS[caches]} || ${force_rebuild} || grep -s -q Bad\ credentials "${__ghhtml}"; then
    _say -n "forced clearing GH html..."
    rm -f "${__ghhtml}"
  fi

  ${__ghSKIP} && echo "<html></html>" > "${__ghhtml}"

  [ ! -f "${__ghhtml}" ] && _say -n "building GH html..." &&
  (
    (
      curl --silent \
        -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${__gh}" \
        -o "${__ghhtml}"
    ) || 
    (
      _fatal "gh html pre-cache failed."
    )
  )

  [ ! -f "${__ghhtml}" ] || [ ! -s "${__ghhtml}" ] &&
    _fatal "${__ghhtml} is missing or empty"

  if grep -q Bad\ credentials "${__ghhtml}"; then _fatal "${__ghhtml} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghhtml}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghhtml} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  #########
  # pre-cache api.github
  _say -n "checking GH caches..."

  if ${BFLAGS[caches]} || ${force_rebuild} || grep -s -q Bad\ credentials "${__ghrjson}"; then
    _say -n "forced clearing GH caches..."
    rm -f "${__ghrjson}"
  fi

  ${__ghSKIP} && echo "{ }" > "${__ghrjson}"

  [ ! -f "${__ghrjson}" ] && _say -n "building GH caches..." &&
  (
    (
      curl --silent \
        -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${__ghr}" \
        -o "${__ghrjson}"
    ) || 
    (
      _fatal "gh-api pre-cache failed."
    )
  )

  [ ! -f "${__ghrjson}" ] || [ ! -s "${__ghrjson}" ] &&
    _fatal "${__ghrjson} is missing or empty"

  if grep -q Bad\ credentials "${__ghrjson}"; then _fatal "${__ghrjson} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghrjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrjson} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  #########
  # pre-cache countribor counts from api.github
  _say -n "checking GH contributor caches..."

  #${force_rebuild} &&
  if ${BFLAGS[caches]} || ${force_rebuild} || grep -q Bad\ credentials "${__ghrjson}"; then
    _say -n "forced clearing GH credential caches..."
    rm -f "${__ghrcontribjson}"
  fi

  ${__ghSKIP} && echo "{ }" > "${__ghrcontribjson}"

  [ ! -f "${__ghrcontribjson}" ] &&
    _say -n "building GH contributor caches..." &&
    (
      (
        cp /dev/null "${__ghrcontribjson}"
        #
        # 500 contrib counter limit
        # othewise would need to clone/count commits like hipcheck
        #
        for pg in 1 2 3 4 5
          do
             curl --silent \
               -H "Accept: application/vnd.github+json" \
               -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
               "${__ghr}/contributors?per_page=100&page=${pg}" 
          done >> "${__ghrcontribjson}"
      ) ||
      (
       _fatal "gh-api contrib pre-cache failed."
      )
    )

  [ ! -f "${__ghrcontribjson}" ] &&
    _fatal "${__ghrcontribjson} is missing or empty"

  if grep -q Bad\ credentials "${__ghrcontribjson}"; then _fatal "${__ghrcontribjson} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghrcontribjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrcontribjson} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  #########
  # pre-cache SBOM
  _say -n "checking GH SBOM caches..."

  if ${BFLAGS[caches]} || ${force_rebuild} || grep -q Bad\ credentials "${__ghrjson}"; then
    _say -n "forced clearing GH SBOM caches..."
    rm -f "${__ghrsbomjson}"
  fi

  ${__ghSKIP} && echo "{ }" > "${__ghrsbomjson}"

  [ ! -f "${__ghrsbomjson}" ] && _say -n "building GH SBOM caches..." &&
  (
    (
      curl --silent \
        -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${__ghr}/dependency-graph/sbom" \
        -o "${__ghrsbomjson}"
    ) ||
    (
      _fatal "gh-api SBOM pre-cache failed."
    )
  )

  [ ! -f "${__ghrsbomjson}" ] || [ ! -s "${__ghrsbomjson}" ] &&
    _fatal "${__ghrsbomjson} is missing or empty"

  if grep -q Bad\ credentials "${__ghrsbomjson}"; then _fatal "${__ghrsbomjson} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghrsbomjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrsbomjson} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  #########
  # pre-cache phylum projects
  _say -n "checking Phylum project caches..."

  { ${BFLAGS[caches]} || ${force_rebuild}; } &&
    _say -n "forced clearing PH project caches..." && rm -f "${__phy_prjs}"

  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "${puri},$(makePuri "${puri}")" > "${__phy_prjs}"

  #
  # TODO: fix paginate.limit, this will work for phylum accounts
  #       with 100 or less projects, any more and a loop is
  #       needed to retrieve all the project ids
  #
  [ ! -f "${__phy_prjs}" ] &&
    _say -n "building Phylum project caches..." &&
    (
      (
        curl --silent --request GET \
          --url 'https://api.phylum.io/api/v0/projects/?paginate.limit=100' \
          --header 'accept: application/json' \
          --header "authorization: Bearer $(phylum auth token --bearer)" \
          -o "${__phy_prjs}"
      ) ||
      (
        _fatal "phylum-api project pre-cache failed."
      )
    )

  [ ! -f "${__phy_prjs}" ] || [ ! -s "${__phy_prjs}" ] &&
    _fatal "${__phy_prjs} is missing or empty"

  _say "OK"

  [ "$(find "${__phy_prjs}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__phy_prjs} over ${_cache_days}(s) days old, consider rebuilding (-f)"

  return
}

consolidate_issues()
{
  local __grepo
  local __lic
  local _liseq
  local _site
  local _id

  cp /dev/null "${3}"

  for __risk__ in "vulnerabilities" "maliciousCodeRisk" "engineeringRisk" "licenseRisk" "authorsRisk"
  do #{
    #
    # ran into an instance when the _dep_prds.json file did
    # NOT have a .issues[] toplevel key, and it could be
    # because at the time the job was incomplete. the jq
    # before the slurp below ensures there is an .issues[]
    # key in the event the key is not present in the json
    #
    [[ "${__risk__}" == "licenseRisk" ]] && _liseq=0 && find . -name \*_ghapi.json -print0 | \
      xargs -0 \
      jq -r '.git_url,.license.spdx_id' | \
      while read -r __grepo; read -r __lic
      do
        ((_liseq++));
	#
	# this RE for the grep is based on results from the licenseDB.json file
	# if it changes, this RE need to change. This RE will only match those
	# licenses from the DB file which have the properties in the query:
	# jq -r '.licenses[]|\
	#  select (.properties.discloseSource == "true" or .properties.networkUseIsDistribution == "true")|\
	#  .spdxId' ../settings/mychecks/licenseDB.json
	# TODO: figure a way to auto-gen this RE
	#
	! grep -s -q -E '(MPL|GPL|OSL|MS-RL|EUPL|LPPL|EPL)' <<<"${__lic}" && continue
        _site=$(sed 's^git://^^g;s^.git$^^g' <<<"${__grepo}")
	_id=$(grep -i --fixed-string "${_site}" ./*_dep_prjs.csv | cut -d, -f2 | tr  '\n' ';' | sed 's/;$//g')
        cat <<-_MYLICEOF
  {
    "tag": "HL$(printf %.4d "${_liseq}")",
    "id": "${_id}",
    "title": "$(sed '0,/*:/{s/[[:alpha:]]*://};s/\(.*\):/\1@/' <<<"${_id}") has a copyleft, restricted, license",
    "description": "### Summary\nPackage owners declare a copyleft open source software license ${__lic}.\n\n### Impact\nUse and/or modification could compel disclosure of source code back to the open source software community.\n\n### References\n$(grep -i --fixed-string "${_site}" ./*_dep_prjs.csv | cut -d, -f2 | tr  '\n' ';' | sed 's/;$//g') from ${__grepo}\n\n### Recommendation\nDo not modify code in this module without understanding the open source software license and any disclosure requirements.\n",
    "severity": "high",
    "domain": "license",
    "details": null,
    "impact": "high",
    "riskType": "licenseRisk"
  }
_MYLICEOF
      done | \
        jq --slurp 'unique_by(.title,.description,.tag,.id)|sort_by(.tag)' >> "${3}"
    # jq's arg _risk in quotes is NOT to be a shell expansion
    # false positive https://github.com/koalaman/shellcheck/issues/1160
    # shellcheck disable=2016
    find . \( -name \*_dep_prds.json -o -name \*deps.json \) -print0 | \
      xargs -0 \
      jq -r --arg _risk "${__risk__}" '
        .
        | if (.issues) then . else . + {"issues": []} end
        | if (.dependencies) then . else . + {"dependencies": [ { "issues":[] } ]} end
        | .issues[],.dependencies[].issues[]
        | select(.riskType==$_risk)
      ' | \
          jq --slurp 'unique_by(.title,.description,.tag,.id)|sort_by(.tag)' >> "${3}"
  done #}

  return 0
}

_do_issues_reports()
{

  { [ ! -f "${__ghrjson}" ] || [ ! -f "${__ghrcontribjson}" ] || [ ! -f "${__phy_prjs}" ] || [ ! -f "${3}" ]; } && _fatal "caches need to be built first"

  cp /dev/null "${4}"
  #
  # TODO: parse arg 1 (e.g., all) for what to make
  #
  # TODO: ensure the slurp is correctly removing dups
  #       investigate jq -s 'unique_by(.title,.descr)'
  #       this unique_by can be destructive if important
  #       keys are not in the unique_by
  #
  # in prep for an HTML presentation, the json structs are
  # converted to tables. the data in the table cells are 
  # filtered using jq's @html filter to create HTML entities
  # furthermore, the curated descriptions at phylum are
  # roughly converted from Markdown to HTML headers for
  # HTML presenation (see 'sed') below in the pipeline.
  #
  # lastly, jq's @html filter does not handle the jq
  # escape character backslash (&bsol; or &#92; i.e. '\')
  # which can cause jq parsing errors like when publishing.
  # As such, jq escape char is now converted to an HTML
  # entity in that same 'sed' filter.
  #
  for __risk__ in "vulnerabilities" "maliciousCodeRisk" "engineeringRisk" "authorsRisk" "licenseRisk"
  do #{
    __impacts__="critical high"
    __label__="Critical and High"
    [[ "${__risk__}" == "licenseRisk" ]] && __impacts__="critical high medium low" && __label__="Critical, High, Medium, and Low"
    jq -r --arg _risk "${__risk__}" --arg _impacts "${__impacts__}" '.[]|select(.riskType==$_risk and .impact==($_impacts|split(" ")|.[]))' "${3}" | \
      jq -r --slurp --arg _risk "${__risk__}" --arg _label "${__label__}" '
        map("<tr><td>" + (.title|@html) + "</td><td>" + (.tag|@html) + "</td><td>" + (.description|@html)  + "</td></tr>")|["<h2>" + $_label + " " + $_risk + "</h2><table><tr><th>Package</th><th>Impact</th><th>Description</th></tr>"] + . + ["</table>"] |
        .[]
      ' | \
      sed 's/\\/\&#92;/g;s^### Overview^<h4>Overview</h4>^g;s^### Proof of Concept^<h4>Proof of Concept</h4>^g;s^### Importance^<h4>Importance</h4>^g;s^### Description^<h4>Description</h4>^g;s^### Summary^<h4>Summary</h4>^g;s^### Impact^<h4>Impact</h4>^g;s^###  Affected Configuration^<h4>Affected Configuration</h4>^g;s^### Patches^<h4>Patches</h4>^g;s^### Workarounds^<h4>Workarounds</h4>^g;s^### For more information^<h4>For more information</h4>^g;s^### Recommendation^<h4>Recommendation</h4>^g;s^### References^<h4>References</h4>^g;s^\*\*CVE\*\*:^<h4>CVE:</h4>^g;s^\*\*CVSS\*\*:^<b>CVSS:</b>^g;' >> "${2}_vulmalrep.html"
  done #}

  return 0
}

produce_BoE()
{
  local _c
  local _chksum

  _c="${1}"

  # assert presence of all required files
  # TODO: add the lockfile used to bootstrap phylum analysis
  #       or add the SBOM that phylum generated after analysis
  #       in order to facilitate repeating the analysis
  ! check_scir_files "${_c}" && _warn "missing files for the BoE" && return 1

  # build tarball
  ! _chksum="$(build_BoE_tarball "${_c}")" && _warn "failed to build the BoE archive (.tgz)" && return 1

  # checksum the tarball
  ! mv "${_c}-scir-p4r-boe.tgz" \
       "${_c}-scir-p4r-boe_sha256:${_chksum}.tgz" && _warn "rename failed" && return 1

  _say "BoE sha256 is: ${_chksum}"
  [[ "${_chksum}" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]] && \
    _warn "chksum is indicative of an empty file, proceed with caution"

  return 0
}

build_BoE_tarball()
{
  local _rc

  _rc=0;

  ! cp /dev/null ../"${1}-scir-p4r-boe.tgz" && \
    _warn "unable to write to ../${1}-scir-p4r-boe.tgz" && _rc=1;

  [[ ! -f ../"${1}-scir-p4r-boe.tgz" ]] && _say "abandoning tarball" && return 1

  ! tar cfz ../"${1}-scir-p4r-boe.tgz" --exclude="*scir-p4r-boe*.tgz*" -C .. "${1}"/ && \
    _warn "tar failed" && _rc=1;

  ! mv ../"${1}-scir-p4r-boe.tgz" . && \
    _warn "unable to move ../${1}-scir-p4r-boe.tgz" && _rc=1;

  sha256sum "${1}-scir-p4r-boe.tgz" | cut -d\  -f1

  return "${_rc}"
}

check_scir_files()
{
  local _rc
  local _cmd
  local _fil
  local _dir

  _rc=0
  #
  # the binaries
  #
  for _cmd in sha256sum tar
  do
    [ -z "$(command -v ${_cmd})" ] &&
      _err "required command, ${_cmd}: not found in path or not installed" &&
      _rc=1
  done

  #
  # the folders (which is it possible there is nothing there)
  # so not a hard error
  #
  for _dir in deps.d subdeps.d
  do
    [ ! -d "${_dir}" ] &&
      _warn "expected directory, ${_dir}: not found for ${1}, continuing"
  done

  #
  # warn if it is believed there are no lockfiles present
  # in the working folder (it is possible there is nothing
  # so it is not a hard error)
  # source: https://docs.phylum.io/docs/supported_lockfiles
  #
  # NOTE: although SBOMs are recognized by phylum, such are
  #       not the source of lockfiles being searched here.
  #
  _fil=$(
    ls -1 \
      ./*_sbom.json \
      ./*package-lock.json \
      ./*npm-shrinkwrap.json \
      ./*yarn.lock \
      ./*pnpm-lock.yaml \
      ./requirements*.txt \
      ./*Pipfile.lock \
      ./*poetry.lock \
      ./*Gemfile.lock \
      ./*.csproj \
      ./*packages.lock.json \
      ./*packages.*.lock.json \
      ./*effective-pom.xml \
      ./*gradle.lockfile \
      ./*go.sum \
      ./*Cargo.lock \
      2>/dev/null
    )
  [ -z "${_fil}" ] && _warn "no lockfiles found for the BoE, copy source lockfiles and rebuild the BoE if this is an error, continuing"

  #
  # the files
  #
  # TODO: determine if job files are required
  #
  for _fil in "${__ghrjson}" \
              "${__ghrsbomjson}" \
              "${__ghrcontribjson}" \
              "${__ghhtml}" \
              "${__phy_prjs}" \
              "${__component_dep_graph}" \
              "${__component_prds}" \
              "${__component_prjs}" \
              "${1}_coalesce.csv" \
              "${1}_scir.json" \
              "${1}_allIssues.json" \
              "${1}_vulmalrep.html" \
              "${1}_scir.html" \
              "${1}"_job_*.json
  do
    [ ! -f "${_fil}" ] &&
      _err "required file, ${_fil}: not found for ${1}" &&
      _rc=1;
  done

  return "${_rc}"
}

#
# will error off if the expected resource and/or values
# need at runtime are not present or unknown for
# binary/commands, docker images, environment vars, and
# command line args
#
check_runtime()
{
  _rc=0 # 0 = no error, 1 = non recoverable error

  #
  # the binaries
  #
  for cmd in jq curl docker base64 phylum iconv "${_OSSFCS}"
  do
    [ -z "$(command -v "${cmd}")" ] &&
      _err "required command, ${cmd}: not found in path or not installed" &&
      _rc=1
  done

  #
  # the docker images
  #
  if ! ${_sudo} docker image ls > /tmp/dimg.${$} 2>&1; then
    _warn "docker: sudo required see /tmp/dimg.${$} for more details"
    _sudo="sudo -E"
  fi

  local -n dimg
  for dimg in _OSSFSC _MITRHC
  do
    _info "config docker image ${!dimg}=${dimg}"
    local _dimgFile
    _dimgFile=$(${_sudo} docker image ls ${dimg} | grep -E -v "REPOSITORY")
    [ -z "${_dimgFile}" ] &&
      _err "required docker image, ${dimg}: not found" &&
      _rc=1
  done

  #
  # check configs/settings/etc. used during runtime
  # TODO: yaml all this stuff
  #
  [[ ! -d "${_OSSSCIRsettings}" ]] && {
    if [[ ! -d "$(dirname "$(realpath "${0}")")/settings" ]]; then
      _err "No settings directory found: ${_OSSSCIRsettings}"
      _rc=1
    else
      _OSSSCIRsettings="$(dirname "$(realpath "${0}")")/settings"
      _MITRHCconfig="${_OSSSCIRsettings}/hipcheck/config"
      _MITRHCscripts="${_OSSSCIRsettings}/hipcheck/scripts"
      _OSSSCIRlicenseDB="${_OSSSCIRsettings}/mychecks/licenseDB.json"
    fi
  }

  local -n _sp
  for _sp in _MITRHCconfig _MITRHCscripts _OSSSCIRlicenseDB
  do
    _info "config setting ${!_sp}=${_sp}"
    [[ ! -r "${_sp}" ]] && _err "can't find path/file for ${!_sp}=${_sp}" && _rc=1
  done

  #
  # made sure these are all readable by container processes, error off if otherwise
  #
  [[ (( $(find "${_MITRHCconfig}" -type d -perm -o=rx|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCconfig}, use chmod o+rx ${_MITRHCconfig}/" && _rc=1
  [[ (( $(find "${_MITRHCconfig}" -type f -perm -o=r|wc -l) -lt 5 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCconfig}, use chmod o+r ${_MITRHCconfig}/*" && _rc=1
  [[ (( $(find "${_MITRHCscripts}" -type d -perm -o=rx|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCscripts}, use chmod o+rx ${_MITRHCscripts}/" && _rc=1
  [[ (( $(find "${_MITRHCscripts}" -type f -perm -o=r|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCscripts}, use chmod o+r ${_MITRHCscripts}/*" && _rc=1
  [[ (( $(find "${_OSSSCIRlicenseDB}" -perm -o=r|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_OSSSCIRlicenseDB}" && _rc=1

  #
  # grab version numbers for report metadata
  #
  _ossf_scorecard_ver="$(${_sudo} docker run --rm "${_OSSFSC}" version 2>&1 | grep GitVersion | cut -d: -f2 | sed 's/ //g')"
  [[ -z "${_ossf_scorecard_ver}" ]] && _warn "could not determine OSSF/Scorecard version" && _ossf_scorecard_ver="unknown"

  _mitre_hipcheck_ver="$(${_sudo} docker run --rm "${_MITRHC}" --version | cut -d\  -f2)"
  [[ -z "${_mitre_hipcheck_ver}" ]] && _warn "could not determine MITRE Hipcheck version" && _mitre_hipcheck_ver="unknown"

  _phylum_ver="$(phylum --version | cut -d\  -f2)"
  [[ -z "${_phylum_ver}" ]] && _warn "could not determine Phylum CLI version" && _phylum_ver="unknown"

  _ossf_critscorecard_ver="$(${_OSSFCS} -depsdev-disable https://github.com/ 2>&1 | grep criticality_score@ | cut -d@ -f2|cut -d/ -f1|sort|uniq)"
  [[ -z "${_ossf_critscorecard_ver}" ]] && _warn "could not determine OSSF/criticality_score version" && _ossf_critscorecard_ver="unknown"

  #
  # the env
  # TODO: allow a token to be passed on the CMD line (getopt)
  #       or pulled from secrets
  #
  # one var for this loop is okay for now
  # shellcheck disable=2043
  for eVar in GITHUB_AUTH_TOKEN
  do
    if [[ -z "${!eVar}" ]]; then
      _err "required env variable, ${eVar}: not set"
      _rc=1
    fi
  done

  local _bearer
  if ! _bearer=$(phylum auth token --bearer); then _say "got token? ${?}"; fi
  [ -z "${_bearer}" ] &&
      _err "required phylum bearer token not available, see 'phylum auth status' for details" &&
      _rc=1

  #
  # the command line
  #
  [ -z "${component}" ] &&
    _err "required local project name not specified (e.g., -C fleetth)" &&
    _rc=1

  [ -z "${phylum_project}" ] &&
    _err "required phylum project name not specified (e.g., -P fleetth)" &&
    _rc=1

  #
  # TODO: fix - this is an unnecessary restriction
  #
  [ ! "${component}" = "${phylum_project}" ] &&
    _err "required phylum and local project must be the same TODO: fix (e.g., -P fleetth -C fleetth)" &&
    _rc=1

  [ "${gh_site}" = "${__NULLGH__}" ] &&
    _warn "Github project site not specified for ${component} (e.g., -G ossf/scorecard)"

  if ! [[ "${_cache_days}" =~ ^[0-9]+$ ]]; then
    _err "cache days setting is numeric: ${_cache_days} is non-numeric" &&
    _rc=1
  fi

  return ${_rc}
}

_saveOff_json_scores()
{
  local _card
  local _scrs
  local _tt=""

  _card="${1}"

  case "${_card}" in
    MYscore | HCscore)
      _tt="gt";
      ;;
    CIOscore | SCscore | PHYscore)
      _tt="le";
      ;;
    CSscore)
      local _cs
      local _pf
      _cs="$(jq -r '.default_score' "${2}")"
      _pf=passing
      [[ -z "${_cs}" ]] && _cs="${__NAN__}"
      ! _fotp --warnFlag "${_cs}" "${_CSthreshold}" >/dev/null && _pf=failing
      _scrs="{  \"checkName\": \"CriticalityScore\", \"checkStatus\": \"${_pf}\", \"score\": ${_cs}, \"weight\": null, \"threshold\": ${_CSthreshold}, \"goal\": ${_CSthreshold}, \"description\": \"Criticality Score\", \"details\": null }"
      echo "${_scrs}"
      return 0
      ;;
    *)
      _warn "saveOff: invalid _card: ${_card/*:}";
      echo ""
      return 1
      ;;
  esac

  unset -n _sarray; declare -n _sarray; _sarray="${_card/score/checkScores}"
  unset -n _tarray; declare -n _tarray; _tarray="${_card/score/checkThresholds}"
  unset -n _warray; declare -n _warray; _warray="${_card/score/checkWeights}"
  unset -n _larray; declare -n _larray; _larray="${_card/score/checkLabels}"

  _scrs=""
  for _c in "${!_sarray[@]}"
  do
    local _pf=passing
    ! _fotp "${_sarray["${_c}"]}" "${_tarray["${_c}"]}" "${_tt}" >/dev/null && _pf=failing
    [[ "${__CHECKNOTIMPL__}" == "${_sarray["${_c}"]}" ]] && _pf=untested
    _scrs="${_scrs}, {  \"checkName\": \"${_c}\", \"checkStatus\": \"${_pf}\", \"score\": ${_sarray["${_c}"]}, \"weight\": ${_warray["${_c}"]}, \"threshold\": ${_tarray["${_c}"]}, \"goal\": ${_tarray["${_c}"]}, \"description\": \"${_larray["${_c}"]}\", \"details\": null }"
  done

  _scrs="${_scrs//NoImp/null}"

  echo "${_scrs/,}"
  return 0
}

_compile_json_p4report()
{
  _say "Compiling report..."
  #
  # there be heredoc here!
  #
  json_data=$(
  cat <<-_JSONEOF
{
 "reportWriter": [
 {
   "id": "Section___OSS_Project_Overview",
   "value": "${__SECTION__}",
   "label": "Overview",
   "risk": ""
 },
 {
   "id": "Background",
   "value": "$(_background "${__ghrjson}")",
   "label": "Background",
   "risk": ""
 },
 {
   "id": "App_Library",
   "value": "Manual (ask)",
   "label": "Application or Library",
   "risk": "context of use"
 },
 {
   "id": "Current_as_of",
   "value": "Date: $(date +%m-%d-%Y) (project queried $(_as_of "${__ghrjson}"))",
   "label": "Current as of",
   "risk": ""
 },
 {
   "id": "OSSP4R_Outlook",
   "value": "$(_p4_outlook "${_SCcard}" "${_HCcard}" "${__component_prds}" | sed 's/"/\\"/g' | tr -d '\n\r')",
   "label": "OSS-P4/R Outlook",
   "risk": ""
 },
 {
   "id": "DODCIO_Criteria",
   "value": "$(_cio_criteria "${_SCcard}" "${_HCcard}" "${__component_prds}" | sed 's/"/\\"/g' | tr -d '\n\r')",
   "label": "DOD CIO Criteria",
   "risk": ""
 },
 {
   "id": "Summarized_Scores_By_Criteria",
   "value": "$(_summary_scores_criteria_tbl | sed 's/"/\\"/g' | tr -d '\n\r')",
   "label": "Summarized Scores By CIO Criteria",
   "risk": ""
 },
 {
   "id": "Section___Security",
   "value": "${__SECTION__}",
   "label": "Security",
   "risk": "Considers "
 },
 {
   "id": "Trusted_Source",
   "value": "Source: ${__gh}<br/>DCARS Availability: Manual<br/>Repo or Mirror: Manual",
   "label": "Trusted Source(s)",
   "risk": "project is a copy of a source code management system that is not visibile to the public."
 },
 {
   "id": "Public_private",
   "value": "$(_pub_priv "${__ghrjson}")",
   "label": "Public or Private",
   "risk": ""
 },
 {
   "id": "Fully_unrestricted",
   "value": "$(_unrestricted "${__ghrjson}")",
   "label": "Fully Unrestricted",
   "risk": ""
 },
 {
   "id": "Login_credentials",
   "value": "$(_login_cred "${__ghrjson}")",
   "label": "Login Credentials",
   "risk": ""
 },
 {
   "id": "Use_Repo_Protections",
   "value": "$(_repo_protections "${_SCcard}")",
   "label": "Use of Repository Protections",
   "risk": "vulnerable to intentional malicious code injection, repository compromise"
 },
 {
   "id": "Has_Large_Commits",
   "value": "$(_large_commits "${_SCcard}" "${_HCcard}") (Churn)",
   "label": "Large Commits",
   "risk": "large commits may increase the risk of successful malicious contribution"
 },
 {
   "id": "Obfuscated_Code",
   "value": "$(_obscure_code "${_SCcard}" "${_HCcard}") (Entropy)",
   "label": "Obfuscated Code",
   "risk": "presence of packed malware or obfuscated code could carry malicious content"
 },
 {
   "id": "Have_Binary_Artifacts",
   "value": "$(_binary_artifacts "${_SCcard}" "${_HCcard}")",
   "label": "Binary Artifact(s)",
   "risk": "Non-reviewable code"
 },
 {
   "id": "Typosquatting_Risk",
   "value": "$(_typo_risk "${component}_allIssues.json" "${_SCcard}" "${_HCcard}")",
   "label": "Typosquatting Risk",
   "risk": "typos for known names can be used to subtly inject malware through dependencies and confusion"
 },
 {
   "id": "Eng_Risk",
   "value": "$(_eng_risk "${component}_allIssues.json")",
   "label": "Engineering Risk",
   "risk": ""
 },
 {
   "id": "Malicious_Code",
   "value": "$(_mal_code "${component}_allIssues.json")",
   "label": "Malicious Code",
   "risk": ""
 },
 {
   "id": "Vuln_Check",
   "value": "$(_vul_check "${component}_allIssues.json" "${_SCcard}")",
   "label": "Known Vulnerabilities",
   "risk": ""
 },
 {
   "id": "Section___Integrity",
   "value": "${__SECTION__}",
   "label": "Integrity",
   "risk": "Considers "
 },
 {
   "id": "Conduct_Peer_Reviews",
   "value": "$(_peer_reviews "${_SCcard}" "${_HCcard}")",
   "label": "Peer Reviews",
   "risk": ""
 },
 {
   "id": "Use_Code_Security_Scanners",
   "value": "$(_code_scanners "${_SCcard}" "${_HCcard}")",
   "label": "Use of Code and Security Scanners",
   "risk": ""
 },
 {
   "id": "Signed_Commits",
   "value": "Manual",
   "label": "Signed Commits",
   "risk": ""
 },
 {
   "id": "Crypto_Signed_Commits",
   "value": "Manual",
   "label": "Cryptographically Signed Commits",
   "risk": ""
 },
 {
   "id": "Crypto_Signed_Releases_Artifacts",
   "value": "$(_signed_releases "${_SCcard}")",
   "label": "Cryptographically Signed Releases &amp; Artifacts",
   "risk": ""
 },
 {
   "id": "Section___Dependencies",
   "value": "${__SECTION__}",
   "label": "Dependencies",
   "risk": "Considers "
 },
 {
   "id": "SBOM",
   "value": "$(_sbom_val "${__ghrsbomjson}")",
   "label": "Published Software Bill of Materials",
   "risk": ""
 },
 {
   "id": "Dependencies_pinned",
   "value": "$(_dep_pinned "${_SCcard}")",
   "label": "Dependencies Pinned to Version",
   "risk": ""
 },
 {
   "id": "Dependencies_up_to_date",
   "value": "$(_dep_up2date "${_SCcard}")",
   "label": "Dependencies Up to Date",
   "risk": ""
 },
 {
   "id": "Dependencies_number_primary_other_OSS",
   "value": "Primary: $(_project_dep "${component}" "${__component_prjs}" | tr -d '\n\r')<br/>Secondary and tertiary: $(_project_dep --subs "${component}" "${__component_prjs}" | tr -d '\n\r')",
   "label": "Number OSS Dependencies",
   "risk": ""
 },
 {
   "id": "Dependencies_number_primary_other_Proprietary",
   "value": "Primary: Manual<br/>Secondary and tertiary: Manual",
   "label": "Number Proprietary Dependencies",
   "risk": ""
 },
 {
   "id": "Section___Malicious_Actors",
   "value": "${__SECTION__}",
   "label": "Malicious Actors",
   "risk": "Considers "
 },
 {
   "id": "Bad_Author_Vuls",
   "value": "Manual",
   "label": "Author(s) Known to Commit Vulnerabilities",
   "risk": ""
 },
 {
   "id": "Bad_Author_Malicious",
   "value": "$(_badactors "${__component_prds}" "${_HCcard}")",
   "label": "Author(s) Known to Commit Malicious Code",
   "risk": ""
 },
 {
   "id": "Section___Long_Term_Support",
   "value": "${__SECTION__}",
   "label": "Long Term Support",
   "risk": "Considers risk factors that indicate whether a software module will be adequately supported over the life of the program"
 },
 {
   "id": "Project_Background_Reprise",
   "value": "$(_background "${__ghrjson}")",
   "label": "Project",
   "risk": "project is stale with little to no changes in recent history"
 },
 {
   "id": "User_Org",
   "value": "$(_user_org "${__ghrjson}")",
   "label": "Individual or Organization",
   "risk": ""
 },
 {
   "id": "Org_type_DUNS_code",
   "value": "$(_org_type "${__ghrjson}")",
   "label": "Organization Type",
   "risk": "project is managed by an individual rather than a more formal organization for support"
 },
 {
   "id": "SLSA_Level",
   "value": "$(_slsa_level "${__ghhtml}")",
   "label": "SLSA Level",
   "risk": ""
 },
 {
   "id": "Best_Practices",
   "value": "$(_best_practices "${_SCcard}" "${_HCcard}")",
   "label": "Best Practices",
   "risk": "project is possibly not following security best practices"
 },
 {
   "id": "Abandoned_Projects",
   "value": "$(_abandoned_prjs "${__ghrjson}")",
   "label": "Number of Abandoned Project(s)",
   "risk": "abandoned projects may have faults and vulnerabilities that may never by fixed"
 },
 {
   "id": "OSSF_Crit_Score",
   "value": "$(_criticality_score "${_CScard}") (higher's better)",
   "label": "OSSF's Activity (criticality) Score (work in progress)",
   "risk": "https://openssf.org/blog/2023/07/28/understanding-and-applying-the-openssf-criticality-score-in-open-source-projects/"
 },
 {
   "id": "Days_Last_Commit",
   "value": "Days since last commit: $(_day_last "${__ghrjson}")<br/>Days since first commit: $(_day_first "${__ghrjson}")<br/>Activity: $(_maintained "${_SCcard}" "${_HCcard}")",
   "label": "Commits",
   "risk": "project is stale with little to no changes in recent history"
 },
 {
   "id": "Core_Contrib_Maintainer_Count",
   "value": "Core: $(_maintainers "${_SCcard}" "${_HCcard}")<br/>Other: $(_contrib_count "${__ghrcontribjson}")<br/>Organizational diversity: $(_contrib_org "${_SCcard}" "${_HCcard}")",
   "label": "Number of Contributors",
   "risk": "a few trusted reviews for long term and the maintainers are active in managing the project"
 },
 {
   "id": "Problem_Reporting_Process",
   "value": "$(_problem_reporting "${__ghrjson}")",
   "label": "Problem Reporting Process",
   "risk": ""
 },
 {
   "id": "Vul_Reporting_Process",
   "value": "$(_vulsec_reporting "${_SCcard}")",
   "label": "Vulnerability Reporting Process",
   "risk": ""
 },
 {
   "id": "Section___Suitability",
   "value": "${__SECTION__}",
   "label": "Suitability",
   "risk": "Considers "
 },
 {
   "id": "License_Name",
   "value": "$(_license_name "${__ghrjson}" | sed 's^ SPDX_ID^<br/>SPDX_ID^g')",
   "label": "License",
   "risk": ""
 },
 {
   "id": "License_Risk",
   "value": "$(_license_risk "${component}_allIssues.json")",
   "label": "License Risk",
   "risk": ""
 },
 {
   "id": "Section___Report_Metadata",
   "value": "${__SECTION__}",
   "label": "OSS-P4/R Information",
   "risk": ""
 },
 {
   "id": "Metadata_create",
   "value": "$(date)",
   "label": "Created",
   "risk": ""
 },
 {
   "id": "Metadata_version",
   "value": "${_version}",
   "label": "Version",
   "risk": ""
 },
 {
   "id": "Metadata_phyprjid",
   "value": "$(_phylum_prjId "${phylum_project}" "${__phy_prjs}")",
   "label": "$(if [ "${puri}" != "${__NULLPURI__}" ]; then echo -n "Package URI"; else echo -n "Phylum Project ID"; fi)",
   "risk": ""
 },
 {
   "id": "Metadata_phyjobid",
   "value": "$(_phylum_jobReport --readOnly "${phylum_project}" "${__component_prds}")",
   "label": "Phylum Analysis ID",
   "risk": ""
 },
 {
   "id": "Metadata_runtime",
   "value": "Approximately $(_thisRuntime "${__logfil}") minute(s) (this run), for a total of $(_totalRuntime 'run-*log')",
   "label": "Runtime",
   "risk": ""
 },
 {
   "id": "Metadata_cmdline",
   "value": "${_cmdline}",
   "label": "Command line",
   "risk": ""
 },
 {
   "id": "Metadata_cardDepth",
   "value": "${scoreDepth}",
   "label": "Score depth",
   "risk": ""
 },
 {
   "id": "Metadata_comment",
   "value": "${_HTMLcaveats[@]}",
   "label": "Comment/Caveats",
   "risk": ""
 },
 {
   "id": "Metadata_credits",
   "value": "<a href='https://github.com/ossf/scorecard'>OSSF/Scorecard ${_ossf_scorecard_ver}</a>, <a href='https://github.com/ossf/criticality_score'>OSSF/Critical Score ${_ossf_critscorecard_ver}</a>, <a href='https://github.com/mitre/hipcheck'>MITRE Hipcheck ${_mitre_hipcheck_ver}</a>, <a href='https://phylum.io'>Phylum.io ${_phylum_ver}</a>",
   "label": "Powered by",
   "risk": ""
 },
 {
   "id": "Metadata_footnotes",
   "value": "${_HTMLfootnotes[@]}",
   "label": "footnotes",
   "risk": ""
 }
 ],
 "rawScores": [
   {
     "mycheck": [ $(_saveOff_json_scores "MYscore") ],
     "criticalityScore": [ $(_saveOff_json_scores "CSscore" "${_CScard}") ],
     "scorecard": [ $(_saveOff_json_scores "SCscore") ],
     "hipcheck": [ $(_saveOff_json_scores "HCscore") ],
     "phylum": [ $(_saveOff_json_scores "PHYscore") ]
   }
 ]
}
_JSONEOF
)
  #
  # heredoc done here
  #
  _say "done."

  echo "${json_data}"
  return
}

###############################
###############################
# __main__ () from entrypoint
###############################
###############################
#
__main__()
{
  local _rc

  ${BoEonly} && ${build_BoE} && {
    # ! pushd "${component}" && _fatal "working directory for ${component} not found"
    _say "Only producing the BoE for ${component}";
    if ! produce_BoE "${component}"; then
      _fatal "BoE production failed for ${component}"
    fi;
    return
  }

  build_caches

  ! ${protectNoUpdate} && [ -s "${__component_prds}" ] && {
    __jobStatus="$(_phylum_jobStatus "${phylum_project}" "${__component_prds}")";
    _phylum_jobId_BHDT="true"
    [[ "${__jobStatus}" == "incomplete" ]] && { \
      _say "Existing phylum analysis job was ${__jobStatus}, rebuilding ${__component_prds}";
      component_dep_rebuild="true";
    }
    _job="$(_phylum_jobId "${phylum_project}" "${__component_prds}")"
    [[ -n "${_job}" ]] && [[ "${__jobStatus}" == "complete" ]] && \
      [[ "${phylum_project}_job_${_job/,*/}.json" -nt "${__component_prds}" ]] && { 
        _say "Existing phylum analysis job is ${__jobStatus} but newer, rebuilding ${__component_prds}";
        component_dep_rebuild="true";
    }
  }

  _level=1
  ${BFLAGS[deps]} && component_dep_rebuild="true"
  (${component_dep_rebuild} || ${force_rebuild} ||
    [ ! -s "${__component_prds}" ] || [ ! -s "${__component_prjs}" ]) &&
      _say "rebuilding links to ${component} dependencies..." &&
      _phylum_dep_components "${component}" "${__phy_prjs}" \
        "${__component_prds}" "${__component_prjs}" "${_level}" &&
      scorecard_rebuild="true" &&
      echo 0,"${__gh}","${__gh}","${__gh}",000 >> "${__component_prjs}"

  #
  # TODO: go n levels deep on dependencies
  #       based on phylum API
  #       still under test not happy with output yet
  #
  #        [ ! -s "${__component_prjs}".subs ]) &&
  ${BFLAGS[subdeps]} && component_subdep_rebuild="true"
  { ${force_rebuild} || ${component_subdep_rebuild} ||
    [ ! -s "${__component_prjs}" ]; } &&
      _say "rebuilding links to ${component} sub-dependencies..." &&
      _phylum_subdep_components "${__component_prds}" "${__component_prjs}"

  #
  # if there is a _tmp_dep_graph then take that structure
  # and build a Graphviz formatted digraph
  #
  [[ -f "${__tmp_dep_graph}" ]] && _say "building digraph of dependencies..." && _build_digraph "${__tmp_dep_graph}" && rm "${__tmp_dep_graph}"

  #
  # TODO: only remove ${component}_coalesce.csv
  #       if and only if after rebuilding, any files
  #       in deps.d are newer than
  #       ${component}_coalesce.csv
  #
  # TODO: build_scorecard ALSO when a dependency
  #       has changed. the hack to 'true' fakes
  #       that for now. need to implement
  #       may be that any *[sh].json is newer than _coalesce.csv
  #
  { ${BFLAGS[cards]} || ${scorecard_rebuild} || ${force_rebuild} ||
    [ ! -d deps.d/ ]; } &&
      _say "rebuilding scorecards for ${component} dependencies..." &&
      build_scorecards "${__ghrjson}" "${__component_prjs}" "${scoreDepth}"

  #
  # TODO: only validate if building scorecards
  #       above resulted in a change
  #
  # shellcheck disable=2143
  [ -f "${component}_coalesce.csv" ] &&
    [[ -n "$(find . -newer "${component}_coalesce.csv" -type f \
        \( -path "*/deps.d/*[sh]c.json*" -o \
           -path "*/subdeps.d/*[sh]c.json*" -o \
           -path \*hc.txt \) \
           -print | \
        grep -v -E '(skip)')" ]] && \
        _say "Detected updated/new scores" && newScores=true

  ${BFLAGS[scores]} && newScores=true
  (${newScores} || ${force_rebuild} ||
    [ ! -d deps.d/ ] || [ ! -s "${component}_coalesce.csv" ]) &&
      _say "validating scorecards for ${component} dependencies..." &&
      validate_scorecards "${__component_prjs}" "${scoreDepth}"

  #
  # TODO: add Project, Policy, and Protection
  #       OSS-P4/R scores from SC scorecard (only)
  #       to the coalesced scores file
  #
  coalesce_header="true"
  (${newScores} || ${force_rebuild} ||
    [ ! -s "${component}_coalesce.csv" ]) &&
      _say "coalescing scores for ${component}..." &&
      coalesce_scorecards "${component}" "${__component_prjs}" "${component}_coalesce.csv"

  #
  # TODO: create a coalesce product score file from all
  #       phylum dependent products (not sure about
  #       this as phylum scores are on products not
  #       projects (as one OSS project may have more
  #       than one product)
  #

  #
  # consolidate issues (vuls, malcode, etc.)
  # TODO: integrate something like this to
  # consolidate the issues if any of the files used to
  # perform that consolidation have been updated
  #  [[ \
  #    $(find . -newer apisix-latest_scir.html \
  #      -a \( -name \*_dep_prds.json -o -name \*deps.json \) \
  #      | wc -l) -gt 0 \
  #  ]] && echo out of date
  #
  { ${BFLAGS[issues]} || ${force_rebuild} ||
    [ ! -s "${component}_allIssues.json" ]; }  &&
      _say "consolidating issues for ${component}..." &&
      consolidate_issues "all" "${component}" "${component}_allIssues.json"

  #
  # TODO: only build html issue report if older
  #       than the json structure it depends on
  #
  (true || "${do_reports}" ||
    [ ! -s "${component}_vulmalrep.html" ]) &&
      _say "building issues report for ${component}..." &&
      _do_issues_reports "${report_type}" "${component}" "${component}_allIssues.json" "${component}_vulmalrep.html"

  #
  # MY checks results don't persist, so run every time
  # TODO: store MY check scores and set proper
  #       dependencies to build_scorecards and run
  #       on when needed
  #
  _run_mychecks "${__ghrjson}"

  #
  # Report summary OSS-P4/R
  #
  # TODO: Current should be current as of the latest cache
  #
  _localdepdir="deps.d/$(mkdepdir "${gh_site}")"
  _CScard="${_localdepdir}/$(basename "${_localdepdir}").cs.json"
  _SCcard="${_localdepdir}/$(basename "${_localdepdir}").sc.json"
  _HCcard="${_localdepdir}/$(basename "${_localdepdir}").hc.json"

  #
  # Set Thresholds for the report
  _set_thresholds "${_SCcard}" "${_HCcard}" "${__component_prds}"

  #
  # comprehends results from the Phylum, scorecard, hipcheck,
  # criticality score
  #
  touch "${component}_scir.json"

  _compute_p4_scores "${_SCcard}" "${_HCcard}" "${__component_prds}"

  json_data="$(_compile_json_p4report)"

  #
  # TODO: make report using confluence template
  #       from data collected in summary
  #       output file
  #
  _say -n "Generating ${component}_scir.json...";
  echo "${json_data}" > "${component}_scir.json"
  _say -n "Checking ${component}_scir.json...";
  _rc="Failed"
  jq -r '.' "${component}_scir.json" > /dev/null && _rc="OK"
  _say "${_rc}"

  #
  # TODO: scrub .value to ensure data in the table
  #       is valid (like '&' becomes '&amp;', jq
  #       has a filter for this and there is a pkg
  #       containing txt2html which might work as well
  #
  [[ "${_rc}" == "OK" ]] && {
    _say -n "Generating ${component}_scir.html...";
    _rc="Failed"
    jq -r '.reportWriter |
      map("<tr><td>" + .label + "</td><td>" + (.value | tostring) + "</td></tr>") | 
      ["<table><tr><th>OSS Project Report</th><th>Response</th></tr>"] + . + ["</table>"] |
      .[]
      ' "${component}_scir.json" > "${component}_scir.html" && _rc="OK"
    _say "${_rc}"
  }

  ${build_BoE} && {
    _say -n "Producing the BoE for ${component}...";
    if ! produce_BoE "${component}"; then
      _fatal "BoE production failed for ${component}"
    fi;
  }

  return
}

readonly _bldFlags="'all', or one or more of: cards,caches,deps,subdeps,meta,crit,scard,hcheck,scores,issues,job"
readonly _indFlags="caches cards crit deps hcheck issues job meta scard scores subdeps"

declare -A BFLAGS=( \
  [caches]="false" \
  [cards]="false" \
  [crit]="false" \
  [deps]="false" \
  [hcheck]="false" \
  [issues]="false" \
  [job]="false" \
  [meta]="false" \
  [scard]="false" \
  [scores]="false" \
  [subdeps]="false" \
  )

declare -A BFLAGSTEXT=( \
  [all]="acts as if all BUILD FLAGS are true, essentially rebuilds everything from scratch (logs retained)" \
  [caches]="cached data from github (home page, contributors, SBOM), phylum project data" \
  [cards]="forces all scorecards and checks to run and retry previous error, no cached data is changed" \
  [crit]="forces OSSF Criticality Score to refresh" \
  [deps]="rebuilds all primary dependencies" \
  [hcheck]="forces MITRE Hipcheck to refresh" \
  [issues]="rebuilds phylum issues from all dependencies" \
  [job]="rechecks phylum analysis job for updates" \
  [meta]="forces GitHub Metadata to refresh" \
  [scard]="forces OSSF Scorecard to refresh" \
  [scores]="rebuilds coalesced scores from all scorecards and checks" \
  [subdeps]="rebuilds all tertiary and deeper dependencies" \
  )

_set_bldFlags()
{
  local _flag

  [[ -z "${1}" ]] && return 1

  for _flag in $(tr ',' '\n' <<<"${1}" | sort);
  do
    case ${_flag,,} in
      all) force_rebuild="true"
           for _indf in ${_indFlags}
           do
             BFLAGS[${_indf}]="false"
           done
           ;;
      caches|cards|crit|deps|hcheck|issues|job|meta|scard|scores|subdeps)
           BFLAGS[${_flag,,}]="true"
           ;;
      *)
           return 1
           ;;
    esac
  done

  return 0
}

###############################
###############################
# __entrypoint__ ()
###############################
###############################
#{

#
# for GitHub API ratelimiting
# attempt to pause/wait rather than
# erroring when script reaches
# API rate limits (does not work
# for subcommand limits--not sure
# how to test for that
#
_lowerLimit=100

#
# values for projects do change
# over time, here just setting
# an arbitary aging of the caching
#
_cache_days=2

build_BoE="false"
BoEonly="false"
protectNoUpdate="false"
blockNetwork="false"

force_rebuild="false"
#
# finer grained rebuild flags
# component_dep_rebuild is dependent on the analysus job (or SBOM change)
# component_subdep_rebuild is dependent on component_dep_rebuild
#
# TODO: introduce more which are set
#       by way of inter-report dependencies
#
component_dep_rebuild="false"
component_subdep_rebuild="false"
scorecard_rebuild="false"
newScores="false"

do_reports="false"
quiet="false"
verbose="false"
scoreDepth=0
scoreTimeout=""

component=
puri="${__NULLPURI__}"
report_type=
gh_site="${__NULLGH__}"
phylum_project=${component}

_sudo=""
#
# errors always go to stderr
#
_fderr=2
_fdwarn=2

#
# never send to stdout
#
_fdverbose=/dev/null
__logger="cat"
__logfil="${__NULLLOG__}"

_cmdline="${0} ${*}"

while getopts "c:f:hlopqvBC:D:G:L:OP:U:VW:" opt; do #{
  case $opt in
    c) _cache_days="${OPTARG}" ;;
    f) ! _set_bldFlags "${OPTARG}" && _fatal "build_flags: expecting ${_bldFlags}"
       ;;
    l) __logfil="run-$(date +%Y%m%d-%H%M%S).log" ;;
    o) BoEonly="true"; build_BoE="true" ;;
    p) protectNoUpdate="true" ;;
    q) quiet="true" ;;
    v) verbose="true" ;;
    B) build_BoE="true" ;;
    C) component="${OPTARG}"; phylum_project="${component}" ;;
    D) scoreDepth="${OPTARG}"
       ! [[ ${scoreDepth} =~ ^[0-9]+$ ]] && \
         [[ ${scoreDepth} != "all" ]] && \
         _fatal "expecting a positive integer for scoreDepth (${scoreDepth})" 
       ;;
    L) do_reports="true" report_type="all" ;;
    G) gh_site="${OPTARG}"
       __ghSKIP="false"
       [ "${gh_site}" = "${__NULLGH__}" ] &&
         _warn "" &&
         __ghSKIP="true"
       ;;
    O) blockNetwork="true" ;;
    P) phylum_project="${OPTARG}" ;;
    U) puri="${OPTARG}" ;;
    V) echo "Version: ${_version}" && _fatal "" ;;
    W) scoreTimeout="${OPTARG}"
       ! [[ ${scoreTimeout} =~ ^[0-9]+$ ]] && \
         [[ ${scoreTimeout,} != "default" ]] && \
         _fatal "expecting a positive integer for scoreTimeout (${scoreTimeout})" 
         [[ ${scoreTimeout,} == "default" ]] && scoreTimeout="${__TIMEOUT__}"
       ;;
    h|*) cat <<-_OPTSEOF
  USAGE: ${0} [OPTIONS]

  OPTIONS

  -c:  set number of days for cache staleness check (default: 2)
  -f:  force rebuild (overrides -p) of all or specific(s) caches, scores, reports or other data
       comma separate being ${_bldFlags}
  -h:  this message (and exit)
  -l:  log output messages to file of the form 'run-YYYYMMDD-HHMMSS.log' in 'logs' folder
  -o:  build only the BoE (i.e., do nothing else but that, and exit. see -B)
  -p:  protect, no automatic updates (useful for reproducibility)
  -q:  quiet (overrides verbose, warnings)
  -v:  verbose, not quiet
  -B:  build body of evidence (.tgz) suitable for archive storage
  -C:  set local component name/project name (REQUIRED)
  -D:  set depth on dependencies to run scorecards (default: 0, top component only, or 'all' (no limit))
  -G:  set Github project site (REQUIRED)
  -L:  make one or more subreports and exit (default 'all')
  -O:  offline - do not use networking (some capabilities will be degraded) relies on cached data
  -P:  set Phylum.io project name (default: same as -C) (REQUIRED)
  -U:  use package URI spec rather than a Phylum.io project name (e.g., npm:@babel/highlight:^7.18.6)
  -V:  display version (and exit)
  -W:  watch docker scorecards run not to exceed time limit (default: ${__TIMEOUT__} seconds)

  BUILD FLAGS (-f 'flag1[,flag2,...]')

$(for _indf in all ${_indFlags}
do
_tabs='\t'
(( ${#_indf} < 5 )) && _tabs='\t\t'
echo -e "  ${_indf}:${_tabs}${BFLAGSTEXT[${_indf}]}"
done)

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
[[ -n "${__logfil}" ]] && \
        __logger="tee -a ${__logfil}" && \
        date +%s > "${__logfil}" && \
        _rp="$(realpath -e "${__logfil}")"

_say "cmdline: ${_cmdline}"

#
# do any overriders here
#
${protectNoUpdate} && { ${force_rebuild} || ${BFLAGS[job]}; } &&
  _warn "-f overrides (forced job rebuild) -p, automatic updates are re-enabled" &&
  protectNoUpdate="false"

#
# check runtime requirements
#
if ! check_runtime; then _fatal "exiting due to missing runtime requirement(s)"; fi

_say "establishing componment working folder ${component}"
mkdir -p "${component}"

_say "setting current working folder to ${component}"
pushd "${component}" || _fatal "can't set working folder to ${component}"

#
# since 'preMVP 240507a (branch: main)' tidy
# up all logfiles to a logs folder, work
# legacy runs to this same folder
#
mkdir -p logs/
[[ -d logs ]] && find  . -maxdepth 1 -name 'run-*.log' -print0 | xargs -0 -I {} mv {} ./logs/

#
# this log file will be moved later in cleanup
#
[[ -n "${__logfil}" ]] && mv -f "${_rp}" "."

#
# caches
#
#   phylum
#
__phy_prjs="phylum_prjs.json"
#
# prds are the product version dependencies
#
__component_prds="${component}"_dep_prds.json
#
# prjs are the projects that make the products
#
__component_prjs="${component}"_dep_prjs.csv
#
# dependency graph in Graphviz format
#
__tmp_dep_graph="$(mktemp -u -p .)"
__component_dep_graph="${component}_dep_digraph.txt"

# https://api.github.com/repos/:owner/:repo
# https://github.com/:owner/:repo
#
#   GitHub (from -G getopts)
#
# TODO: since SCIR-OSS requires a -G for the project home.
#       BUT using -U, I may see that the packageURI (e.g.,
#       cargo:liblzma-sys:0.3.2) might have a .repoURL (e.g.,
#       portable-network-archive/liblzma-rs) THEREFORE it should
#       be possible when in the -U state to glean the -G
#       from .repoURL and set these accordingly
#
__gh=https://github.com/${gh_site}
__ghr=https://api.github.com/repos/${gh_site}
__ghhtml=$(basename "${gh_site}")_gh.html
__ghrjson=$(basename "${gh_site}")_ghapi.json
__ghrsbomjson=$(basename "${gh_site}")_ghapi_sbom.json
__ghrcontribjson=$(basename "${gh_site}")_ghapi_contrib.json

#
# if running offline (-O) there has to be cached files
# fatally error off if the cache files are not available
#
${blockNetwork} && ! check_scir_files "${component}" && \
  _fatal "cache files missing for offline mode" && return 1

#
# enerythings set, now, get to work
#

__main__

_cleanup_and_exit 0
#}
