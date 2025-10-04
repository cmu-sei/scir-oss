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
# bash exitpoint search down for _cleanup_and_exit (often rearchable from _fatal)
#

readonly _version="pubRel 251003 (branch: publicRelease)"

#
# check_runtime will confirm these settings
# if the path does not exist, it will be updated
# to realpath for arg 0, if that fails _fatal error will
# be raised
#
# TODO: make this 'settings' folder path/name a command line arg
#
_OSSSCIRsettings=${_OSSSCIRsettings:-"$(dirname "$(realpath "${0}")")/settings"}
_MITRHCconfig="${_OSSSCIRsettings}/hipcheck/config"
_MITRHCscripts="${_OSSSCIRsettings}/hipcheck/scripts"
_MITRHCcache=""
_OSSSCIRlicenseDB="${_OSSSCIRsettings}/mychecks/licenseDB.json"
[[ -f "${_OSSSCIRsettings}/scir-oss/_dig4repo-resolv.csv" ]] && _OSSSCIRrepoResolveDB="${_OSSSCIRsettings}/scir-oss/_dig4repo-resolv.csv"
_CAStoreVolume=
_CAStoreDocker=

#
# experimental blacklists
# blacklists are purl/pkg specs to ignore from dependency digging
# this are implemented at three levels, primary, secondary, and
# teritary (including beyond). the blacklist is a regex which is
# used to ignore dependencies (i.e., referenceLocator)
#
# examples:
# export _PRIMARY_BLACKLIST="pkg:githubactions|pkg:github"
# export _SECONDARY_BLACKLIST="${_PRIMARY_BLACKLIST}|pkg:composer"
# export _TERTIARY_BLACKLIST="${_SECONDARY_BLACKLIST}|pkg:npm"
# idea: _TERTIARY_BLACKLIST="4/${_SECONDARY_BLACKLIST}|pkg:npm"
#       to mean levels 4 and above
# primary components excluded from dependency search are those matching
#   githubactions and github; secondary components are the same with the
#   addition of composer; and teritary and beyond ignores all those as
#   well as npm.
#
readonly _NULL_BLACKLIST_="__NULL_BLACKLIST__"
_PRIMARY_BLACKLIST="${_PRIMARY_BLACKLIST:-${_NULL_BLACKLIST_}}"
_SECONDARY_BLACKLIST="${_SECONDARY_BLACKLIST:-${_NULL_BLACKLIST_}}"
_TERTIARY_BLACKLIST="${_TERTIARY_BLACKLIST:-"pkg:npm|^npm:"}"

# env var to check json files pulled via curl
# mostly for debug purposes
#
# this does incur overhead runtime when enabled/true
#
_debugVerifyCurlJsons="${_debugVerifyCurlJsons:-false}"

#
# simply utilities
#

err_report() {
    _warn --q "Error on line (see .basherr in logs/) $1"
}

trap 'err_report $LINENO' ERR

#
# make sure to handle / process logfile
#
_cleanup_and_exit()
{
  [[ -s "${__logfil}.basherr" ]] && _warn "${component}/logs/${__logfil}.basherr: inspect for bash errors."
  _say "oss-p4/R done."
  [[   "${__logfil}" == "${__NULLLOG__}" ]] && rm -f "${__logfil}"
  [[ ! "${__logfil}" == "${__NULLLOG__}" ]] && [[ -d logs/ ]] && [[ -f "${__logfil}" ]] && mv "${__logfil}" logs/ && mv -f "${__logfil}.basherr" logs/
  [[ ! -s "logs/${__logfil}.basherr" ]] && rm -f "logs/${__logfil}.basherr"

  rm -f "${__RATELIMIT__}"
  rm -f "${__RUNTIME__}"
  #
  # shellcheck disable=2164
  ! dirs -v |tail -1 | grep -q '^ 0' && popd >&"${_fdverbose}"
  exec 7>&-
  exit "${1}"
}

_say()
{
#  [[ -s "${__logfil}.basherr" ]] && _debug "There are errors in ${__logfil}.basherr"
  echo "${1}" "${2}" | ${__logger} >&"${_fdverbose}" && return
}

_info()
{
  _HTMLcaveats+=("I: ${*}<br/>")
  echo INFO: "${*}" | ${__logger} >&"${_fdwarn}" && return
}

_warn()
{
  local _cav
  _cav="true"

  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --q ]] && _cav="false"
    shift 1
  done
  "${_cav}" && _HTMLcaveats+=("W: ${*}<br/>")
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
  _HTMLcaveats+=("F: ${*}<br/>")
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
  # in the '[]' below become '_' sed ''
  echo "${1}" | sed 's^https://github.com/^^g;s^/^___^g;s/[*^~<>#@]/_/g'
  return 0
}

# https://stackoverflow.com/questions/6250698/how-to-decode-url-encoded-string-in-shell
# TODO: there may be better answers in the post, explore better
#       yes - there is garbage out there, with embedded control chars
function urldecode() { local i="${*//+/ }"; echo -ne "${i//%/\\x}" | tr -d '[:cntrl:]'; }

#
# OSS-P4/R report writer helpers
#

#
# confluence-specific HTML
#
readonly __REDFLAG__="<ac:emoticon ac:name='cross'/>"
readonly __REDSVGFLAG__='<svg width="16" height="16" viewBox="0 -0 100 100"><circle cx="50" cy="50" r="40" fill="red" /><path d="M30 30 L70 70" stroke="white" stroke-width="8" stroke-linecap="round"/><path d="M70 30 L30 70" stroke="white" stroke-width="8" stroke-linecap="round"/></svg>'
readonly __WARNING__="<ac:emoticon ac:name='warning'/>"
readonly __WARNINGSVG__='<svg width="16" height="16" viewBox="0 0 100 100"><path d="M50 10 L90 90 H10 Z" fill="yellow" stroke="black" stroke-width="4"/><line x1="50" y1="35" x2="50" y2="60" stroke="black" stroke-width="6" stroke-linecap="round"/><circle cx="50" cy="72" r="4" fill="black"/></svg>'
readonly __SECTION__="<hr style='border: 10px solid gray; border-radius: 5px'/>"

readonly __NULLGH__=":owner/:repo"
readonly __NULLPURI__=":eco:name:ver"
__NULLLOG__="$(mktemp -u -p . -t nulllog.XXXXXXXXXX)"
__RUNTIME__="$(mktemp -u -p . -t thisrun.XXXXXXXXXX)"
readonly __NULLLOG__
readonly __TIMEOUT__="300"
readonly __SBOM__="SBOM"
readonly __PHYLUM__="PHYLUM"
readonly __GITHUB__="GITHUB"
readonly __NOASSERTION__="unknown"

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
  [MYscore]="ProjectForked DepProjectsForked TertiaryProjectsForked" \
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
  [MYscore]="SanctionedAuthor ProjectRestrictiveLicense DepProjectsRestrictiveLicense TertiaryProjectsRestrictiveLicense" \
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
  [MYscore]="ProjectForked DepProjectsForked TertiaryProjectsForked" \
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
  [MYscore]="SanctionedAuthor ProjectRestrictiveLicense DepProjectsRestrictiveLicense TertiaryProjectsRestrictiveLicense" \
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
# these are populated dynamically
#
declare -A SCcheckScores
declare -A SCcheckMessage

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
declare -A HCcheckMessages

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
  [DepProjectsForked]="${__NAN__}" \
  [TertiaryProjectsForked]="${__NAN__}" \
  [ProjectRestrictiveLicense]="${__NAN__}" \
  [DepProjectsRestrictiveLicense]="${__NAN__}" \
  [TertiaryProjectsRestrictiveLicense]="${__NAN__}" \
  [SanctionedAuthor]="0" \
  )

declare -A MYcheckLabels=( \
  [UnfixedVulnerabilities]="Unfixed Vuls" \
  [ProjectForked]="Project Forked" \
  [DepProjectsForked]="Dependent Projects Forked" \
  [TertiaryProjectsForked]="Other Projects Forked" \
  [ProjectRestrictiveLicense]="Restrictive License(s)" \
  [DepProjectsRestrictiveLicense]="Dependent Restrictive License(s)" \
  [TertiaryProjectsRestrictiveLicense]="Other Restrictive License(s)" \
  [SanctionedAuthor]="Sanctioned Author" \
  )

# shell checker does not see this is passed by ref
# shellcheck disable=2034
declare -A MYcheckWeights=( \
  [UnfixedVulnerabilities]="${SCcritical}" \
  [ProjectForked]="${SCcritical}" \
  [DepProjectsForked]="${SCmedium}" \
  [TertiaryProjectsForked]="${SClow}" \
  [ProjectRestrictiveLicense]="${SCcritical}" \
  [DepProjectsRestrictiveLicense]="${SChigh}" \
  [TertiaryProjectsRestrictiveLicense]="${SClow}" \
  [SanctionedAuthor]="${SCcritical}" \
  )

declare -A MYcheckThresholds=( \
  [UnfixedVulnerabilities]="0" \
  [ProjectForked]="false" \
  [DepProjectsForked]="0" \
  [TertiaryProjectsForked]="0" \
  [ProjectRestrictiveLicense]="0" \
  [DepProjectsRestrictiveLicense]="0" \
  [TertiaryProjectsRestrictiveLicense]="0" \
  [SanctionedAuthor]="0" \
  )

#
# these are advisory checks
# will not generate a redFlag but a warning
# value is the test (lt, gt, le, ge) of value to threshold
#   warning is emitted if value "test" threshold is true
#   (normally a redFlag would be emitted)
# normally used by plugins
#
declare -A advisoryChecks=( \
  [MYcheck:dummy]="gt"
)

declare -A foundLicenses

declare -A licenseChecks

declare -A SDNhits

#
# lifted from https://stackoverflow.com/questions/4023830/how-to-compare-two-strings-in-dot-separated-version-format-in-bash
# only works on systems with coreutils - see link for alternatives
#
# example:
#   ver_between 1.2 1.3 1.5 && echo "yes" || echo "no"
#
ver_between()
{
  # args: min, actual, max
  printf '%s\n' "$@" | sort -C -V
}

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
  [[ -z "${1}" ]] && echo "${__WARNING__}-1" && return 1

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
  _info "Thresholds for OSSF Scorecard scores set at ${_SCthreshold}"

  #
  # Criticality Score
  _info "Threshold for OSSF Criticality Score set at ${_CSthreshold}"

  # Hipcheck
  #

  # Phylum
  #
  "${_doPhylum}" && {
    _th="$(jq -r '.riskThresholdActions.total.threshold' "${3}")"
    _msg="Thresholds for Phylum set in Phylum.io project account"
    [[ "${_th}" == "null" ]] && _msg="Thresholds for Phylum package URI scores set to ${_PHthreshold}"
    _info "${_msg}"
  }

  # OSS-P4/R
  #
  _info "Local cache tolerance set to ${_cache_days} days"
  _info "Days active tolerance set to ${__ACTIVEDAYS__} days"
  _info "Days for a new project set to ${__DAYSNEW__} days"
  _info "Contributors tolerance set to ${__CONTRIBCNT__} ids"
  _warn "Some responses may require manual investigation if necessary (look for 'manual')"

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

jq_legacyHipcheckScores()
{
#  _debug "${FUNCNAME[0]} WITH ${1}"
  {
    jq -r '.passing[]|[.analysis,"=",.value,"=",.threshold,"=",""]|@csv' "${1}" ;
    jq -r '.failing[]|[.analysis,"=",.value,"=",.threshold,"=",""]|@csv' "${1}" ;
    jq -r '.errored[]|[.analysis,"=",.value,"=",.threshold,"=",.error.source.msg]|@csv' "${1}" ;
  } | sed 's/[",]//g'
  return 0
}

#
# designed to return the same key values as the legacy hipcheck scores
#
jq_newHipcheckScores()
{
  local _func
  local _thr
  local _units
  local _evalStr
#  _debug "${FUNCNAME[0]} with ${1}"
  {
  jq -r '.passing[]|[.name,"=",.final_value,"=",.message,"=",""]|@csv' "${1}"; \
  jq -r '.failing[]|[.name,"=",.final_value,"=",.message,"=",""]|@csv' "${1}"; \
  jq -r '.errored[]|[.name,"=",.final_value,"=",.message,"=",.error.msg]|@csv' "${1}"; \
  } | sed 's/[",]//g' | \
      while IFS="=" read -r check score message errmsg
      do
        check=${check/mitre\//};
        #
        # the thresholds are reported in the message
        # in some cases the units are now part of the threshold and final value
        # strip the units for now (units are only on Activity used to be weeks
        # in the legacy scores now is in days)
        # TODO: be sensitive to the units
        #
        _evalStr="$(
          echo "${message}" | sed 's/ but[[:print:]].*$//g;' \
          | sed 's/^[[:print:]]*\(to be less than or equal to\|to be equal to\)[[:space:]]\([[:digit:]]\.*[[:digit:]]*\|true\)[[:space:]]*\([[:print:]]*$\)/_func="\1"; _thr="\2"; _units="\3"/g'
        )"
        [[ "${message}" != "${_evalStr}" ]] && eval "${_evalStr}"
        [[ -n "${_units}" ]] && score="${score/ ${_units}/}"
        echo "${check^}=${score}=${_thr}=${errmsg}"
        unset _func
        unset _thr
        unset _units
        unset errmsg
      done
  return 0
}

jq_legacyPhylumScores()
{
  local __myphyc

  __myphyc=$(mktemp -u -p . -t legacyScores.XXXXXXXXXX)

  jq -r 'paths(scalars | true) as $p
    | [ ( [ $p[] | tostring ] | join(".") ), ( getpath($p) | tojson )] | join(": ")' \
    "${1}" \
    | grep "riskScores"  1>"${__myphyc}"

  for _domain in total vulnerability malicious_code author engineering license
  do
    echo -n "${_domain}="
    _s=$(grep -o -E "(riskScores.${_domain}:[[:space:]]?[0-9]+([.][0-9]+)?$)" < "${__myphyc}" \
      | cut -d: -f2 \
      | sed 's/^ //g' \
      | sort -n \
      | head -1)
    [[ -z "${_s}" ]] && _s="null"
    echo "${_s}"
  done

  rm -f "${__myphyc}"

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
  if ${__ghSKIP} || [[ ! -s "${1}" ]] || [[ -f "${1}".err ]]; then
    _SCcompositeScore="not run as project skipped or scorecard failed to scan project"
    # TODO make this a loop so as to pickup when new checks are added
    PFourPolicyScores[SCscore]="${__NAN__}"
    PFourProjectScores[SCscore]="${__NAN__}"
    PFourProtectionScores[SCscore]="${__NAN__}"
    PFourProductScores[SCscore]="${__NAN__}"
    CIOlongTermScores[SCscore]="${__NAN__}"
    CIOdependencyScores[SCscore]="${__NAN__}"
    CIOsecurityScores[SCscore]="${__NAN__}"
    CIOintegrityScores[SCscore]="${__NAN__}"
    CIOmalActorsScores[SCscore]="${__NAN__}"
    CIOsuitabilityScores[SCscore]="${__NAN__}"
  else #{
    while IFS="=" read -r check score reason
    do
      [[ "${score}" == "${SCfail}" || -z "${score}" ]] && score="${__NAN__}"
      SCcheckScores["${check}"]="${score}"
      SCcheckMessage["${check}"]="${reason}"
    done < <(jq -r '.checks[]|[.name,"=",.score,"=",.reason]|@csv' "${1}" | sed 's/[",]//g')
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

  local __hcJQ
  local __hcVersion=" (legacy), "
  __hcJQ='jq_legacyHipcheckScores'
  grep -s -q -E '(policy_expr)' "${2}" && { __hcJQ='jq_newHipcheckScores' && __hcVersion=", "; }

  _say -n "HC${__hcVersion}"
  #
  # grab scores from Hipcheck checks
  if ${__ghSKIP} || [[ ! -s "${2}" ]] || [[ -f "${2}".err ]]; then
    _HCscore="not run as project skipped or hipcheck failed to scan project"
    _HCrationale="${_HCscore}"
    # TODO make this a loop so as to pickup when new checks are added
    PFourPolicyScores[HCscore]="${__NAN__}"
    PFourProjectScores[HCscore]="${__NAN__}"
    PFourProtectionScores[HCscore]="${__NAN__}"
    PFourProductScores[HCscore]="${__NAN__}"
    CIOlongTermScores[HCscore]="${__NAN__}"
    CIOdependencyScores[HCscore]="${__NAN__}"
    CIOsecurityScores[HCscore]="${__NAN__}"
    CIOintegrityScores[HCscore]="${__NAN__}"
    CIOmalActorsScores[HCscore]="${__NAN__}"
    CIOsuitabilityScores[HCscore]="${__NAN__}"
  else #{
    while IFS="=" read -r check score threshold reason
    do
      # use NaN to signify errored check
      [[ -z "${score}" ]] && score="${__NAN__}" #&& HCcheckError["${check}"]="${threshold}"
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
      HCcheckMessages["${check}"]="${reason}"
    done < <("${__hcJQ}" "${2}")

    if [[ ${__hcJQ} == 'jq_legacyHipcheckScores' ]]; then
      _HCrationale=$(jq -r '.rationale|@base64d' "${2}" |
        grep Recommendation -A 1 |
        tail -1 |
        tr -d '\r' |
        sed 's/^[ \t]*//;s/[ \t]*$//'
      )
      _HCscore=$(cut -d, -f1 < <(echo "${_HCrationale}") |cut -d\   -f5)
      _HCrationale="$(_fotp "${_HCthreshold}" "${_HCscore}")${_HCrationale}"
    else
      _HCscore=$(jq -r '.recommendation.risk_score' "${2}")
      _HCrationale="$(jq -r '.recommendation.kind' "${2}") as risk rated as ${_HCscore}, acceptable below or equal to ${_HCthreshold}"
      _HCrationale="$(_fotp "${_HCthreshold}" "${_HCscore}")${_HCrationale}"
    fi

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
  grep -s -q -E '(totalRiskScore|total_risk_score)' "${3}" || { __phyJQ='jq_newPhylumScores' && __phyVersion=", "; }

  "${_doPhylum}" && _say -n "PHY${__phyVersion}"

  #
  # grab scores from Phylum.io checks
  "${_doPhylum}" && { while IFS="=" read -r check score
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
  }

  _say -n "MY, "

  #
  # grab scores from MYchecks checks
  if ${__ghSKIP}; then
    # TODO make this a loop so as to pickup when new checks are added
    PFourPolicyScores[MYscore]="${__NAN__}"
    PFourProjectScores[MYscore]="${__NAN__}"
    PFourProtectionScores[MYscore]="${__NAN__}"
    PFourProductScores[MYscore]="${__NAN__}"
    CIOlongTermScores[MYscore]="${__NAN__}"
    CIOdependencyScores[MYscore]="${__NAN__}"
    CIOsecurityScores[MYscore]="${__NAN__}"
    CIOintegrityScores[MYscore]="${__NAN__}"
    CIOmalActorsScores[MYscore]="${__NAN__}"
    CIOsuitabilityScores[MYscore]="${__NAN__}"
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
  [[ "${2/=*}" == "bg" ]] && {
    _beg="<td style='background-color:${2/bg=};'>"
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
  local _wrapper_start
  local _table_start
  local _tablerow_start
  local _tabledata_start
  local _wrapper_end
  local _table_end
  local _tablerow_end
  local _tabledata_end
  local _preamble

  _cols=7

  _preamble="_conf"
  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --www ]] && _preamble="_www"
    shift 1
  done
  _wrapper_start="${_preamble}html_wrapper_start"
  _wrapper_end="${_preamble}html_wrapper_end"
  _table_start="${_preamble}html_table_start"
  _table_end="${_preamble}html_table_end"
  _tablerow_start="${_preamble}html_tablerow_start"
  _tablerow_end="${_preamble}html_tablerow_end"
  _tabledata_start="${_preamble}html_tabledata_start"
  _tabledata_end="${_preamble}html_tabledata_end"

  tblhtml_data=$(
cat <<-_TBLHTMLEOF
$(${_wrapper_start})
  $(${_table_start} "CIO Criteria")
      $(for _card in "Criteria:CIOscore" "__SECTION__:__SECTION__" "MY_Checks:MYscore" "OSSF_Scorecard:SCscore" "MITRE_Hipcheck:HCscore" $( "${_doPhylum}" && echo "Phylum_io:PHYscore" )
      do
        ${_tablerow_start} "${_card/*:}"
        _rowname="${_card/:*}"
        for _label in "${_rowname}" Security:CIOsecurityScores Integrity:CIOintegrityScores Dependencies:CIOdependencyScores Malicious_Actors:CIOmalActorsScores Long-Term_Support:CIOlongTermScores Suitability:CIOsuitabilityScores
        do
           [[ "${_card/*:}" == "__SECTION__" ]] && \
             ${_tabledata_start} "${__SECTION__}" "col=${_cols}" && \
             ${_tabledata_end} && \
             ${_tablerow_end} && \
             continue 2
           if [[ -n "${_rowname}" ]]; then
             ${_tabledata_start} "${_rowname/_/ }" && _rowname=
           else
             unset -n _aarray; local -n _aarray; _aarray="${_label/*:}"
             local _colname="${_label/:*}"
             ${_tabledata_start} "${_colname//_/ } (${_aarray[${_card/*:}]})" "bg=$(_rgb_score "${_aarray[${_card/*:}]}" "10.0")"
           fi
           ${_tabledata_end}
        done
        ${_tablerow_end}
      done)
  $(${_table_end})
$(${_wrapper_end})
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
  local _wrapper_start
  local _table_start
  local _tablerow_start
  local _tabledata_start
  local _wrapper_end
  local _table_end
  local _tablerow_end
  local _tabledata_end
  local _preamble

  _cols=5

  _preamble="_conf"
  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --www ]] && _preamble="_www"
    shift 1
  done
  _wrapper_start="${_preamble}html_wrapper_start"
  _wrapper_end="${_preamble}html_wrapper_end"
  _table_start="${_preamble}html_table_start"
  _table_end="${_preamble}html_table_end"
  _tablerow_start="${_preamble}html_tablerow_start"
  _tablerow_end="${_preamble}html_tablerow_end"
  _tabledata_start="${_preamble}html_tabledata_start"
  _tabledata_end="${_preamble}html_tabledata_end"

  althtml_data=$(
cat <<-_ALTHTMLEOF
$(${_wrapper_start})
  $(${_table_start} "P4 Outlook")
      $(for _card in "Overall:P4score" "__SECTION__:__SECTION__" "MY_Checks:MYscore" "OSSF_Scorecard:SCscore" "MITRE_Hipcheck:HCscore" $( "${_doPhylum}" && echo "Phylum_io:PHYscore" )
      do
        ${_tablerow_start} "${_card/*:}"
        _rowname="${_card/:*}"
        for _label in "${_rowname}" Project:PFourProjectScores Product:PFourProductScores Protection:PFourProtectionScores Policy:PFourPolicyScores
        do
           [[ "${_card/*:}" == "__SECTION__" ]] && \
             ${_tabledata_start} "${__SECTION__}" "col=${_cols}" && \
             ${_tabledata_end} && \
             ${_tablerow_end} && \
             continue 2
           if [[ -n "${_rowname}" ]]; then
             ${_tabledata_start} "${_rowname/_/ }" && _rowname=
           else
             unset -n _aarray; local -n _aarray; _aarray="${_label/*:}"
             local _colname="${_label/:*}"
             ${_tabledata_start} "${_colname//_/ } (${_aarray[${_card/*:}]})" "bg=$(_rgb_score "${_aarray[${_card/*:}]}" "10.0")"
           fi
           ${_tabledata_end}
        done
        ${_tablerow_end}
      done)
  $(${_table_end})
$(${_wrapper_end})
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
      $(for _card in "Criteria:CIOscore" "__SECTION__:__SECTION__" "MY_Checks:MYscore" "OSSF_Scorecard:SCscore" "MITRE_Hipcheck:HCscore" $( "${_doPhylum}" && echo "Phylum_io:PHYscore" )
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
               _bhr="<a href='https://github.com/mitre/hipcheck/blob/hipcheck-v3.3.1/docs/book/src/using/analyses.md'>";
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
             local _wflag=""
             _wwwhtml_tabledata_start "${_hdr}"
             for _check in ${_aarray[${_card/*:}]}
             do
               [[ "${__NOCHECK__}" == "${_check}" ]] && break
               [[ "${__CHECKNOTIMPL__}" == "${_sarray[${_check}]}" ]] || [[ -z "${_sarray[${_check}]}" ]] && continue
               #
               # support advisory warnings in summary
               # assumes all checks are unique
               # TODO: remove the unique assumption
               #
               _wflag=""
               [[ -n "${advisoryChecks["${_check}"]}" ]] && _wflag="--warnFlag" && _tt="${advisoryChecks["${_check}"]}"
               # need _wflag to not be an arg if unset
               # shellcheck disable=2086
               echo -n "$(_fotp ${_wflag} "${_sarray["${_check}"]}" "${_tarray["${_check}"]}" "${_tt}")${_larray[${_check}]}($(_fppp "${_fp}" "${_sarray[${_check}]}")/${_tarray[${_check}]})<br/>"
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

  hcmsg="<a href='https://github.com/mitre/hipcheck/blob/hipcheck-v3.3.1/docs/book/src/using/analyses.md'>MITRE Hipcheck</a>: (score &le; threshold) ${_HCrationale}<br/>(composed of "
  for check in "${!HCcheckScores[@]}"
  do
    # need to wordsplit after "auto" on the HCcheckScores
    # shellcheck disable=2086
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

_maintained()
{
  local _t
  local _v
  local _q

  if [ -s "${1}" ]; then
    _v="${SCcheckScores[Maintained]/${__NAN__}/}"
    _q="${SCcheckMessage[Maintained]}"
    _scmsg="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 with ${_q}";
  else
    _scmsg="No insight from scorecard"
  fi

  # shellcheck disable=2046
  _hcmsg="with no insight from hipcheck"
  if [ -s "${2}" ]; then
    _t="${HCcheckThresholds[Activity]}"
    _v="${HCcheckScores[Activity]/${__NAN__}/}"
    _q="under or at"
    [[ -n "${_v}" ]] && {
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over"
      #
      # TODO: new hc schema reports in days - units are parsed correctly
      #       but parsing is in a subshell - need to get units back to
      #       parent to fix that here: change 'week' to proper unit
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
  local _v
  local _m

  _v="${SCcheckScores[Contributors]/${__NAN__}/}"
  _m="${SCcheckMessage[Contributors]}"
  if [[ -n "${_v}" ]]; then
    _co="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
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
  # TODO: cycloneDX, syft, etc.)
  _v=$(jq -r 'if (.sbom) then .sbom else . end|[ .spdxVersion,.creationInfo.creators ]|@text' "${1}" | sed 's/\[//g;s/\]//g;s/"//g')
  [[ -z "${_v}" ]] && _v="manual";

  echo -n "${_v}"
  return
}

_sbom_pkgs()
{
  echo -n "$(cut -d, -f2 < "${1}" | cut -d: -f1 | sort | uniq -c | sort -nr | grep -vi -E '(http)'| sed 's/^[[:space:]]*\([[:digit:]]\)/\1/' | tr '\n' ','|sed 's/,$//;s/,/, /g')"
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
  local _orgCode

  _orgCode=""
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  [[ $(jq -j '.owner.type' "${1}") == "Organization" ]] && _orgCode=" <br/>${ORGLOOKUP_LABEL}: Manual"

  echo "Pending, see: $(jq -r '.owner.organizations_url' "${1}")${_orgCode}"
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

  ${blockNetwork} &&
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

  _cs=${__NAN__}
  [[ -s "${1}" ]] && _cs="$(jq -r '.default_score' "${1}")"
  echo "$(_fotp --warnFlag "${_cs}" "${_CSthreshold}")$(_fppp "2" "${_cs}")/1.0"
  return
}

_best_practices()
{
  local _bp
  local _v
  local _m

  _v="${SCcheckScores[CII-Best-Practices]/${__NAN__}/}"
  _m="${SCcheckMessage[CII-Best-Practices]}"
  if [[ -n "${_v}" ]]; then
    _bp="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  else
    _bp="${__WARNING__} check for best practices not run"
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
  local _ph

  _c="No restrictive license detected"
  # false positive check
  # shellcheck disable=2102
  [[ -v licenseChecks[restrictive] ]] && _c="Detected $(_fotp "${MYcheckScores[ProjectRestrictiveLicense]}" "${MYcheckThresholds[ProjectRestrictiveLicense]}" gt)${MYcheckScores[ProjectRestrictiveLicense]} restrictive license(s) being: $(echo "${licenseChecks[restrictive]}"| tr ',' '\n' | sort | uniq | tr  '\n' ',' | sed 's/,$//g;s/,/, /g')"

  # false positive check ${__WARNING__}
  # shellcheck disable=2102
  [[ -v licenseChecks[undetermined] ]] && _c="${_c}<br/>Found ${__WARNING__}$(( $(echo "${licenseChecks[undetermined]}" | tr -cd , | wc -c) + 1)) license(s) yet to be determined suitable: ${licenseChecks[undetermined]//,/, }. "

  _p="$(jq -r '.[]|select(.riskType=="licenseRisk")|.title' "${1}" | sed 's/Commercial license risk detected in .*$/Commercial license risk detected/g' | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g')"
  [[ -z "${_p}" ]] && _p="Detected no product or dependent license(s) detected "

  _pi="($(jq -r '.[]|select(.riskType=="licenseRisk")|.impact' "${1}" | sort | uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g'))"
  [[ $_pi == "()" ]] && _pi="no impacts"
  _r="${_p} and ${_pi} potentially reported from dependencies"
  { [[ "${_p}" =~ .*critical*. ]] || [[ "${_p}" =~ .*high*. ]]; } && _r="${__REDFLAG__}${_p}"
  _ph=""
  "${_doPhylum}" && {
    _ph="Phylum reports ($(_fotp "${PHYcheckScores[license]}" "${PHYcheckThresholds[license]}")${PHYcheckScores[license]}): "
  }

  echo "${_c}<p/>${_ph}${_r}"

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

  echo "${_r}"

  return
}

_vul_check()
{
  local _sc
  local _sr
  local _c
  local _r
  local _v
  local _m

  #
  # TODO: see what OSSF scorecard reports
  #_sc="$(jq -r '.checks[]|select(.name?=="Vulnerabilities")|.details|length' "${2}")"
  #_sr="${_sc} vul(s) found in the primary component"
  #[[ "${_sc}" -le "0" ]] && _sr="No vuls found in primary component"

  if [ -s "${2}" ]; then
    _v="${SCcheckScores[Vulnerabilities]/${__NAN__}/}"
    _m="${SCcheckMessage[Vulnerabilities]}"
    _sc="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m} (open, known unfixed vulnerabilities)"
  else
    _sc="no insight from scorecard"
  fi

  #
  # see what Phylum and/or Grype scorecard reports (which can comprehend dependency issues)
  _c="$(jq -r '.[]|select(.riskType=="vulnerabilities")|.impact' "${1}" |
    grep -E '(crit|high|low|med)'|
    sed 's/low/zlow/;'| sort | uniq -c | sort  -k1.9 |
    sed 's/zlow/low/;' | sed 's/^[ \t]*//;s/[ \t]*$//' |
    tr "\n" ";" | sed 's/;/; /g;s/; $//g')";
  _r=".<p/>Other detected vuls including other dependencies identified potentially: ${_c}"

  _crits="$(jq -r '.[]|select(.riskType=="vulnerabilities" and .impact=="critical")|.tag' "${1}" |sort|uniq -c | sed 's/^[ \t]*//;s/[ \t]*$//' | tr "\n" ";" | sed 's/;/; /g;s/; $//g;s/ [CHMI]V[\-]/ /g')"
  _w="<p/>criticals: ${__REDFLAG__}${_crits}"

  [[ -z "${_c}" ]] && _r=". And no additional dependent vul(s) detected"
  [[ -z "${_crits}" ]] && _w=""

  echo "${_sc}${_r}${_w}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_dep_pinned()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local _dpin
  local _v
  local _m

  _v="${SCcheckScores[Pinned-Dependencies]/${__NAN__}/}"
  _m="${SCcheckMessage[Pinned-Dependencies]}"
  _dpin="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  echo "${_dpin}" | tr -d '\n' | sed 's/\n//g;s/\r//g;s/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_dep_up2date()
{
  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  local _sc
  local _sr
  _sc="${SCcheckScores[Dependency-Update-Tool]/${__NAN__}/}"
  _sr="${SCcheckMessage[Dependency-Update-Tool]}"

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

  echo "${_sc} with ${_sr}; investigate if any dependencies apply to more than the pipeline" | sed 's/"//g;s/ ,/ /g'
  return
}

_max_project_dep()
{
  { [[ -f "${1}" ]] && echo -n "$(cut -d, -f1 "${1}"|sort -n|tail -1)"; } || echo -n "${__NOASSERTION__}"
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
  case "${1}" in
    --pri)
      _f="${3}"
      ;;
    --sec)
      _pat='^[2],'
      _f="${3}"
      _found=',200'
      ;;
    --ter)
      _pat='^[012],'
      _mod='-v'
      _f="${3}"
      _found=',200'
      ;;
  esac

  {
    echo -n "Total found: ";
    # shellcheck disable=2126
    _c="$(grep -c ${_mod} -E "(${_pat})" "${_f}")";
    echo "$(_fotp --warnFlag "${_c}" "0")${_c}"
    echo -n ", dependencies pulled: ";
    # shellcheck disable=2126
    _c="$(grep ${_mod} -E "(${_pat})" "${_f}" | grep -c "${_found}")";
    echo "$(_fotp --warnFlag "${_c}" "0")${_c}"
    echo -n ", dependencies unknown: ";
    # shellcheck disable=2126
    _c="$(grep ${_mod} -E "(${_pat})" "${_f}" | grep -c ",404")";
    echo "$(_fotp --warnFlag "${_c}" "1" "ge")${_c}"
  }

  return
}

_code_scanners()
{
  local _t
  local _v
  local _q
  local _msg

  _hcmsg="with no insight from hipcheck"
  if [ -s "${2}" ]; then
    _v="${HCcheckScores[Fuzz]/${__NAN__}/}"
    _q=""
    [[ -n "${_v}" ]] && {
      [ "${_v}" = "false" ] && _q="${__REDFLAG__}not "
      _hcmsg="with repository ${_q}receiving regular fuzz testing";
    }
  fi

  if [ -s "${1}" ]; then
    _v="${SCcheckScores[Fuzzing]/${__NAN__}/}"
    _m="${SCcheckMessage[Fuzzing]}"
    _msg="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m} ${_hcmsg}<br/>"

    _v="${SCcheckScores[SAST]/${__NAN__}/}"
    _m="${SCcheckMessage[SAST]}"
    _msg="${_msg}$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}, and <br/>"

    _v="${SCcheckScores[CI-Tests]/${__NAN__}/}"
    _m="${SCcheckMessage[CI-Tests]}"
    _msg="${_msg}$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  else
    _msg="no insight from scorecard and ${_hcmsg}"
  fi

  echo "${_msg}" | tr -d '\n' | sed 's/\n//g;s/\r//g;s/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_repo_protections()
{
  local _v
  local _m
  local _bp
  local _dw
  local _tp
  local _wh

  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return
  _v="${SCcheckScores[Branch-Protection]/${__NAN__}/}"
  _m="${SCcheckMessage[Branch-Protection]}"
  _bp="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"

  _v="${SCcheckScores[Dangerous-Workflow]/${__NAN__}/}"
  _m="${SCcheckMessage[Dangerous-Workflow]}"
  _dw="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"

  _v="${SCcheckScores[Token-Permissions]/${__NAN__}/}"
  _m="${SCcheckMessage[Token-Permissions]}"
  _tp="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"

  _v="${SCcheckScores[Webhooks]/${__NAN__}/}"
  _m="${SCcheckMessage[Webhooks]}"
  if [[ -n "${_wh}" ]]; then
    _wh="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
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
  local _m
  local _q
  local _verb
  local _scmsg
  local _hcmsg

  if [ -s "${2}" ]; then
    _t="${HCcheckThresholds[Review]}"
    _v="${HCcheckScores[Review]/${__NAN__}/}"
    _q="under"
    _verb="receiving"
    [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over" && _verb="lacking"

    _t2="${HCcheckThresholds[Identity]}"
    _v2="${HCcheckScores[Identity]/${__NAN__}/}"
    _q2="under"
    _verb2="not"
    [[ $(echo "${_v2} > ${_t2}" | bc -l) -eq 1 ]] && _q2="${__REDFLAG__}over" && _verb2="too"
    _hcmsg="with change requests often ${_verb} approving review prior to merge with $(_fppp "$((${#_t}-1))" "$(echo "${_v} * 100" | bc -l)")% ${_q} the $(_fppp "auto" "$(echo "${_t} * 100" | bc -l)")% threshold"
    _hcmsg="${_hcmsg} and commits ${_verb2} often applied by the author with $(_fppp "$((${#_t2}-1))" "$(echo "${_v2} * 100" | bc -l)")% ${_q2} the $(_fppp "auto" "$(echo "${_t2} * 100" | bc -l)")% threshold"
  else
    _hcmsg="with no insight from hipcheck"
  fi

  if [ -s "${1}" ]; then
    _v="${SCcheckScores[Code-Review]/${__NAN__}/}"
    _m="${SCcheckMessage[Code-Review]}"
    _scmsg="Count pending; and activity is $(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  else
    _scmsg="Count pending; and no insight from scorecard"
  fi

  echo "${_scmsg} ${_hcmsg}" | sed 's/"//g;s/ ,/ /g'
  return
}

_large_commits()
{
  local _t
  local _v
  local _q
  local _qq
  local _precision

  if [ -s "${2}" ]; then
    _t="${HCcheckThresholds[Churn]}"
    _v="${HCcheckScores[Churn]/${__NAN__}/}"
    if [ -z "${_v}" ]; then
      _warn "hipcheck analysis, churn, failed to run: ${HCcheckMessages[Churn]}"
      _hcmsg="${__WARNING__}Failed to analyze commits - internal error"
    else
      _q="under or at"
      _qq=" some "
      _precision="auto"
      [[ $(echo "${_v} <= 0" | bc -l) -eq 1 ]] && _precision="$((${#_t}-1))" && _qq=" no "
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _precision="$((${#_t}-1))" && _qq=" " && _q="${__REDFLAG__}over"
      _hcmsg="Detected${_qq}unusually large commits being $(_fppp "${_precision}" "${_v}") found ${_q} the ${_t} permitted threshold"
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
    _t="${HCcheckThresholds[Entropy]}"
    _v="${HCcheckScores[Entropy]/${__NAN__}/}"
    if [ -z "${_v}" ]; then
      _warn "hipcheck analysis, entropy, failed to run: ${HCcheckMessages[Entropy]}"
      _hcmsg="${__WARNING__}Failed to analyze commits - internal error"
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
    _t="${HCcheckThresholds[Binary]}"
    _v="${HCcheckScores[Binary]/${__NAN__}/}"
    _q="under or at"
    [[ -n "${_v}" ]] && {
      [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over";
      _hcmsg="with binaries potentially containing code being ${_v} found ${_q} the ${_t} permitted threshold";
    }
  fi

  if [ -s "${1}" ]; then
    _v="${SCcheckScores[Binary-Artifacts]/${__NAN__}/}"
    _m="${SCcheckMessage[Binary-Artifacts]}"
    _scmsg="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  else
    _scmsg="no insight from scorecard"
  fi

  echo "${_scmsg} ${_hcmsg}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_typo_risk()
{
  local _t
  local _v
  local _q

  if [ -s "${3}" ]; then
    _t="${HCcheckThresholds[Typo]}"
    _v="${HCcheckScores[Typo]/${__NAN__}/}"
    if [ -z "${_v}" ]; then
      _warn "hipcheck analysis, Typo, failed to run: ${HCcheckMessages[Typo]}"
      _hcmsg="${__WARNING__}Failed to analyze for typos - can't identify a known language"
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
  local _v
  local _m
  local _vuls

  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _v="${SCcheckScores[Security-Policy]/${__NAN__}/}"
  _m="${SCcheckMessage[Security-Policy]}"
  _vuls="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  echo "${_vuls}" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
  return
}

_dcoSigned_commits()
{
  echo "Manual"
  return
}

_signed_commits()
{
  local _valid
  local _total

  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _valid="$(jq -r '.[]|[.sha,.commit.verification.verified]|@csv' "${1}" 2>/dev/null|grep -c ,true)"
  _total="$(jq -r '.[]|[.sha,.commit.verification.verified]|@csv' "${1}" 2>/dev/null|grep -c .)"
  [[ "${_total}" == "0" ]] && echo "Manual, no commits detected in ${1}" && return

  #
  # multiply by 10 to get this into the range of 0 - 10
  echo "$(_fotp "$(echo "${_valid} / ${_total} * 10" | bc -l)" "${_SCthreshold}")${_valid} of the last ${_total} commits have a valid cryptographic signature."
  return
}

_signed_releases()
{
  local _v
  local _m
  local _sign
  local _pkg

  ${__ghSKIP} && echo "Unknown, project is not on GitHub" && return

  _v="${SCcheckScores[Signed-Releases]/${__NAN__}/}"
  _m="${SCcheckMessage[Signed-Releases]}"
  _sign="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"

  _v="${SCcheckScores[Packaging]/${__NAN__}/}"
  _m="${SCcheckMessage[Packaging]}"
  _pkg="$(_fotp "${_v}" "${_SCthreshold}")${_v}/10 as ${_m}"
  echo "${_sign}, and<br/>${_pkg}; investigate if any such signing(s) are crytopgraphic" | sed 's/"//g;s/ ,/ /g;s^,/^/^g;'
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
    _hcmsg="No insight from hipcheck"
    if [ -s "${2}" ]; then
    _t="${HCcheckThresholds[Affiliation]}"
    _v="${HCcheckScores[Affiliation]/${__NAN__}/}"
      _q="at or under"
      [[ -n "${_v}" ]] && {
        [[ $(echo "${_v} > ${_t}" | bc -l) -eq 1 ]] && _q="${__REDFLAG__}over"
        _hcmsg="Hipcheck contributors affiliations being ${_v} found ${_q} the ${_t} permitted threshold";
      }
    fi
  fi #}

  local _score
  local _phmsg
  "${_doPhylum}" && if [ -s "${1}" ]; then
    _score="$( jq -r '.riskScores.author' "${1}" )"
    #
    # account for legacy and new Phylum json format
    # assumes compute_p4_scores called before _badactors
    [[ "${_score,,}" == "null" ]] && _score="${PHYcheckScores[author]}"
    _phmsg="No, none reported by Phylum.io."
    [[ ! "${_score}" == "${__NAN__}" ]] && [[ $(echo "${_score}" "<" "1.00" | bc -l) -eq 1 ]] && _phmsg="${__REDFLAG__}Yes, something reported by Phylum.io, investigate."
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

  _f="$(mktemp -u -p . -t runtime.XXXXXXXXXX)"

  for f in ${1} logs/${1}
  do
    [[ ! -f "${f}" ]] && continue;
    _s=$(head -1 "${f}"|grep -E '^[[:digit:]]');
    [[ -z "${_s}" ]] && continue;
    echo $(( $(stat --printf=%Y "${f}") - _s )) >> "${_f}"
  done

  _count=0
  _seconds=0
  [[ -s "${_f}" ]] && {
    _count="$(wc -l < "${_f}")"
    _seconds="$(awk '{s+=$1} END {printf "%.0f", s}' < "${_f}")"
  }

  rm -f "${_f}"
  echo "$(( _seconds / 60 )) minute(s) over ${_count} run(s)"
  return
}

#
# partially follows rules at github.com/package-url/purl-spec/blob/main/PURL-SPECIFICATION.rst
# and                        github.com/package-url/purl-spec/blob/main/VERSION-RANGE-SPEC.rst
#      _cmp="$(_ph_sanitize_cmp "${_c}")"
_ph_sanitize_cmp()
{
  local _c
  local _cmp
  local _cmpgrps
  _c="${1}"

  if [[ "${_c}" =~ ^pkg: ]]; then
    # here _c is reduced (on input) to wack any qualifiers or subpaths in the pkg url
    # false positive check, don't want shell expansion
    # shellcheck disable=2016
    _cmpgrps="$(sed -E 's$^pkg:/*([a-zA-Z0-9.+-]+)/([_a-zA-Z0-9.+-/%]+)([@#\?])*(.*)$_typeg1=\1;_nameg2=\2;_vqsg3=\3;_vqs_valg4=\4;$g' <<<"${_c/%[?#]*/}")"

    # if sed did not match, sed gives back input and here simply give back without touching the invalid purl
    [[ "${_cmpgrps}" == "${_c/%[?#]*/}" ]] && _warn "${_cmpgrps}: invalid purl" && echo "${_c}" && return

    eval "${_cmpgrps}"
    #
    # next need to eliminate version ranges in the purl specification, easiet before decoding
    # shellcheck disable=2154
    [[ ${_vqs_valg4} =~ % ]] && {
      # this will change '%5E11.4.0%2C%20%3C11.4.9' to this '11.4.0'
      # false positive check, don't want shell expansion
      # shellcheck disable=2016
      _cmpgrps="$(sed -E 's$([%][0-9A-F][0-9A-F])*([0-9.]+)*(.*)$\2$' <<<"${_vqs_valg4}")"
      [[ "${_cmpgrps}" != "${_vqs_valg4}" ]] && _vqs_valg4="${_cmpgrps}"
    }
    #
    # for the project csv, make _c look the same as legacy phylum (for now)
    #   form is <type>:<name>:<ver>
    # false positive check, vars are indirectly assigned in a successful match in the sed above
    # shellcheck disable=2154
    _cmp="${_typeg1}:${_nameg2}:${_vqs_valg4}"
    [[ ${_cmp} =~ % ]] && _cmp=$( urldecode "${_cmp}" )
  else
    _cmp="${_c}"
  fi

  echo "${_cmp}"
  return
}

#
# sanitize all github urls to only have :owner:/:repo:
# pattern, no extra paths, no .git at the end or git+ at
# beginning as such fail with GH API and tools that use it
#
_gh_sanitize_url ()
{
  # quick out
  { [[ -z "${1}" ]] || [[ "${1,,}" == "${__NOASSERTION__}" ]] || [[ "${1,,}" == "null" ]]; } && echo "${__NOASSERTION__}" && return;

  local _uriS;
  # wack beginning upto github.com
  # side effect here is that multiple github.com in the same var
  # will end up as one - the last one in the list
  # TODO: smarter file and blacklists like
  #       github.com/sponsors/<:owner> is a valid url
  _uriS="${1/*github.com/github.com}";

  # if no github at the start - also a quick out echo back
  ! [[ ${_uriS,,} =~ ^github.com ]] && echo "${1}" && return

  # sense github.com: to be github.com/
  _uriS="${_uriS/github.com:/github.com\/}"

  #
  # some of these results are old and still use http:
  # fix that here
  #
  [[ ${_uriS,,} =~ ^http: ]] && _uriS="${_uriS/p\:/ps\:}";

  # now ready to cut down to github.com/:owner/:repo
  [[ ${_uriS,,} =~ ^github.com/ ]] && _uriS="$(cut -d/ -f1-3 <<<"${_uriS}")"
  _uriS="${_uriS/%\.git/}"

  grep -o -E '(github.com/[_a-zA-Z0-9-]+/[_a-zA-Z0-9-]+)' <<<"${_uriS}";
  return
}

# see https://guides.rubygems.org/rubygems-org-api/ and
#     https://guides.rubygems.org/rubygems-org-api-v2/
gem_scraper()
{
  local _ret;
  local _srch;
  _srch="${1}"
  _say -n " ${FUNCNAME[0]} for ${_srch}";

  _ret=""
  #
  # try v2 api which includes the version number
  #
  { [[ ${_srch} =~ :v[[:digit:]] ]] || [[ ${_srch} =~ :[[:digit:]] ]]; } &&
    _ret="$(curl --silent --location https://rubygems.org/api/v2/rubygems/"${_srch/%:*}"/versions/"${_srch/#*:}".json | jq -r 'if (.source_code_uri) then (.source_code_uri) else (.homepage_uri) end' 2>/dev/null)";

  #
  # failing that or if no version number given try v1 api without the version number
  #
  [[ -z "${_ret}" ]] &&
    _ret="$(curl --silent --location https://rubygems.org/api/v1/gems/"${_srch/%:*}".json -o - | jq -r 'if (.source_code_uri) then (.source_code_uri) else (.homepage_uri) end' 2>/dev/null)";

  { [[ "${_ret,,}" = "null" ]] || [ -z "${_ret}" ]; } && _ret="${__NOASSERTION__}";
  _gh_sanitize_url "${_ret}";
  return
}

cargo_scraper()
{
  local _ret;
  local _srch;

  # don't need the version number as part of this search
  _srch="${1%[:@]*}"

  _say -n " ${FUNCNAME[0]} for ${_srch}";

  _ret="$(curl --silent --location \
    "https://crates.io/api/v1/crates?page=1&per_page=10&q=${_srch}" -o - \
    | jq -r --arg srch "${_srch}" '
      .crates[]
      | select (.id == $srch)
      | .repository
    ')";

  [ -z "${_ret}" ] && _ret="${__NOASSERTION__}";

  _gh_sanitize_url "${_ret}";
  return
}

golang_scraper()
{
  local _hop
  local _srch
  local _ret

  _srch="${1/%[:@]*}"

  _say -n " ${FUNCNAME[0]} for ${_srch}";

  case "${_srch}" in
    dario.cat/*)
      _ret=$(curl -L --silent --request GET --url "${_srch}" -o -| grep content=\""${_srch}" | grep -o 'github.com/[a-zA-Z0-9]*/[a-zA-Z0-9]*')
      ;;
    google.golang.org/*)
      _ret=$(curl -L --silent --request GET --url "${_srch}" -o - | grep -E -i -A 10 "(repository)" | grep -E -i  "([[:space:]]github)" | sed 's/^[[:space:]]*//g')
      ;;
    golang.org/*|go.opentelemetry.io/*|go.elastic.co/*|cloud.google.com/go/*|go.uber.org/*|gotest.tools/*|go.opencensus.io)
      _hop=$(curl -L --silent --request GET --url "${_srch}" -o - | grep -E href= | cut -d\" -f2)
      _ret=$(curl -L --silent --request GET --url "${_hop}" -o - |grep -E -A 3 Repository |grep -E noopener | cut -d\" -f2)
      ;;
    go.mozilla.org/*)
      _ret=$(curl -L --silent --request GET --url "${_srch}" -o - | grep -E href= | grep source | cut -d\" -f2)
      ;;
    gopkg.in/*)
      _ret=$(curl -L --silent --request GET --url "${_srch}" -o - | grep btn | grep github | cut -d\" -f4)
      ;;
    gocloud.dev)
      _ret=$(curl -L --silent --request GET --url "${_srch}" -o - | grep -E "go-source" | cut -d\" -f4 | cut -d\  -f2)
      ;;
    github.com/*)
      _ret="${_srch}"
      ;;
    *) _ret=""
      _say "unknown golang repo pattern" "${_srch}"
      ;;
  esac

  [ -z "${_ret}" ] && _ret="${__NOASSERTION__}"
  _gh_sanitize_url "${_ret}"
  return
}

#
# dep is: 'npm:@adobe/css-tools:v4.3.3'
# passed is: '@adobe/css-tools:v4.3.3'
# needed:     ^^^^^^^^^^^^^^^^
# pretty much all up and until the ':' version component
# see: https://github.com/npm/registry/blob/main/docs/REGISTRY-API.md#get-v1search
# NB: deprecated packages may not show up (unknown) or match
# a similary named path, e.g, npm:babel-eslint:9.0.0 (deprecated)
# may match pattern like package/@babel/eslint-plugin a false positive!
# should be github.com/babel/babel-eslint rather than falsely github.com/babel/babel
# TODO: fix matching and/or detect deprecated which the jq contains contributes
# TODO: see if the &scope=foo (e.g., @adobe) makes a real difference
# TODO: there may be a rate limiter involved, which needs
#       to be looked into and implemented if so
npm_scraper()
{
  local _ret
  local _srch
  local _htcode
  local _jsonOut
  local _localRetry

  _srch="$(cut -d: -f1 <<<"${1}")"

  _say -n " ${FUNCNAME[0]} for ${_srch}"
  #
  # 1 character len _srch result in a 400 response don't bother
  #
  [[ ${#_srch} -le 1 ]] && _gh_sanitize_url "${__NOASSERTION__}"

  #
  # NB: the search API has a 64 byte limit on the search text
  # NB: there is a 429 code rate limit with the file containing error code: 1015
  # TODO: this is an optimistic search (size=1) is this
  #       too optimistic/narrow - as the json returned
  #       for npm matches are really fuzzy as I can tell
  #
  _jsonOut="$(mktemp -u -p . -t npm_scr.XXXXXXXXXX)"
  _localRetry=1
  while [[ $_localRetry -lt 5 ]];
  do
    _htcode="$(curl --retry 1 --retry-all-errors --fail --silent --location \
      --write-out "%{http_code}" \
      "https://registry.npmjs.com/-/v1/search?text=${_srch:0:64}&size=1" \
      -o "${_jsonOut}")"
    { [[ -f "${_jsonOut}" ]] || [[ ${_htcode} != "429" ]]; } && break;
    _localRetry=$(( _localRetry+1 ));
    _say -n " ${FUNCNAME[0]}: ${_rc} with ${_htcode}"
  done

  _ret="$(jq -r --arg srch "${_srch}" '
      .objects[]
        |.package.links
          |select (.npm |contains($srch))|.repository
    ' "${_jsonOut}")"

  rm -f "${_jsonOut}"
  [ -z "${_ret}" ] && _ret="${__NOASSERTION__}"
  _gh_sanitize_url "${_ret}"
  return
}

#
# dep is: 'maven:com.amazonaws:aws-java-sdk-core:1.11.571'
# passed is: 'com.amazonaws:aws-java-sdk-core:1.11.571'
# OR
# passed is: 'com.amazonaws/aws-java-sdk-core:1.11.571'
# we need:    ^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^ ^^^^^^^^
# becomes:    com/amazonaws/aws-java-sdk-core/1.11.571/aws-java-sdk-core-1.11.571.pom
#
maven_scraper()
{
  local _rc
  local _ret
  local _srch
  local _dom
  local _art
  local _ver

  # here the <name>:<ver> portion of <type>:<name>:<ver> of the arg
  # is being parsed into search components for maven repo
  #
  #eval "$(sed 's/\([[:print:]].*\)[:\/]\([[:print:]].*\)[:@]*[v]*\(.*\)/_ver=\3;_art=\2;_dom=\1/g' <<<"${1}")"
  #eval "$(sed -E 's/^([^:\/?\n]+)[:\/]([^:@?\n]+)[:@]*v*(.*)/_dom=\1;_art=\2;_ver=\3;/mg' <<<"${1}")"
  eval "$(sed -E 's/^([^:\/?\n]+)[:\/]([^:?\n]+)[:@]*v*(.*)/_dom=\1;_art=\2;_ver=\3;/mg' <<<"${1}")"

  { [[ -z "${_ver}" ]] && [[ -z "${_art}" ]] && [[ -z "${_dom}" ]] && _say "${FUNCNAME[0]} for '${1}': malformed" && echo "${__NOASSERTION__}" && return; } || _say "version: '${_ver}' article: '${_art}' domain: '${_dom}'"

   #
   # try for the .pom file first
   # TODO: there are some strange version numbers out there
   #       on thing to do is to mangle the version number 
   #       pattern to try another .pom version - likely ugghh
   #       another thing is to search on the artifact like
   #       npm and select/drill from there.
   #       using central artifact search is kinda a shortcut
   #
  _loc="repo1.maven.org/maven2"
  _srch="${_dom//\./\/}/${_art}/${_ver}/${_art}-${_ver}.pom"

  _jsonOut="$(mktemp -u -p . -t mvn_scr.XXXXXXXXXX)"
  _localRetry=1
  _htcode=
  while [[ $_localRetry -lt 3 ]];
  do
    { [[ -z "${_htcode}" ]] && _say -n " ${FUNCNAME[0]}: trying ${_loc} for ${_srch}"; } || _say -n " ${FUNCNAME[0]}: ${_rc} with ${_htcode} now trying ${_loc} for ${_srch}"

    _htcode="$(curl --retry 1 --retry-all-errors --fail --silent --location \
      --write-out "%{http_code}" \
      "https://${_loc}/${_srch}" \
      -o "${_jsonOut}" \
      )"

    _rc="${?}"

    [[ ! -f "${_jsonOut}" ]] && cp /dev/null "${_jsonOut}"

    case "${_loc}" in
      repo1.maven.org/maven2)
        _ret="$(grep -B 10 -E '(</scm>)' "${_jsonOut}" | grep -E '(<url>)' | grep github)"
        ;;
      central.sonatype.com/artifact)
        _ret="$(grep -o 'github.com/[^:"/]*/[^:"/]*' "${_jsonOut}" | sort | uniq )"
        ;;
      *)
        ;;
    esac

    #
    # likely github hit - we are done
    #
    [[ -n "${_ret}" ]] && [[ "${_htcode}" == "200" ]] && break

    #
    # second try as the prev curl may have 404'ed
    # or the .pom may not have referenced github
    # this second try appears to be more time costly
    #
    _localRetry=$(( _localRetry+1 ));
    _srch="${_dom}/${_art}"
    _loc="central.sonatype.com/artifact"
  done

  rm -f "${_jsonOut}"

  [ -z "${_ret}" ] && _ret="${__NOASSERTION__}"
  _ret="${_ret/#*<url>}"
  _gh_sanitize_url "${_ret/%<\/url>}"
  return
}

#
# inspired by https://github.com/hugovk/pypi-tools/blob/main/source_finder.py
#
# dep is: 'pypi:jira:>=3.1.1'
# passed is: 'jira:>=3.1.1'
# we need:    ^^^^   ^^^^^
# becomes:    jira/3.1.1/json
# and there is this pattern: pypi:typed-ast:<2,>=1.4.0
# it seems at the moment, passing 'jira/json' is also acceptable
# so may not need to deal with version range specifications
#
pypi_scraper()
{
  local _ret;
  local _srch;
  local _jsonOut;

  _jsonOut="$(mktemp -u -p . -t pyp_scr.XXXXXXXXXX)"

  _srch="${1%[:@]*}"

  _say -n " ${FUNCNAME[0]} for ${_srch}";

  #
  # TODO: check return codes, seen instances where
  #       a srch resulted in nothing but then later
  #       hits
  #
  curl --silent --location \
    "https://pypi.org/pypi/${_srch}/json" -o "${_jsonOut}"

  _ret="$(jq -r 'if (.info.project_urls.GitHub) then .info.project_urls.GitHub else .info.project_urls[]? end' "${_jsonOut}")"

  case $(grep -c -i "github.com/" <<<"${_ret}") in
  0) # nothing with github.com clear results
    _ret=""
    ;;
  1) # no op only 1 github.com/ hit let pass thru
    :
    ;;
  *) # uggh more than one try to figure out the right one
    # is the search name in the possible github.com/ urls
    _candret="$(grep -i "github.com/" <<<"${_ret}" | grep -E "(${_srch})")"
    if [[ -n "${_candret}" ]]; then
      # yep - go with that one
      _ret="${_candret}"
    else
      # no search name match and more than one github.com - sort uniq and hope for one
      # TODO: find a better way like fuzzy matching
      _ret="$(grep -i "github.com/" <<<"${_ret}" | sed 's^[[:space:]].*https://^https://^g;s/"$/",/g' | sort | uniq)"
    fi
    ;;
  esac

  rm -f "${_jsonOut}"

  [ -z "${_ret}" ] && _ret="${__NOASSERTION__}";
  _gh_sanitize_url "${_ret}";
  return
}

_dig4repo_hint()
{
  #
  # commas around the search is needed to ensure only exact matches
  #
  grep --fixed-strings ,"${2}", "${1}"  |cut -d, -f4
  return
}

#
# invokes custom scrapers to scrape a site or API
# looking for and URL/URI pointing to GitHub
#
# must return "unknown" (${__NOASSERTION__} ) OR "" if not known
#
_dig4repo()
{
  local _eco
  local _scraper_fn
  local _ret

  _ret="${__NOASSERTION__}"

  { [[ -z "${1/%null/}" ]] || [[ "${1}" =~ ^github.com/ ]]; } &&
    _gh_sanitize_url "${1/%null/${__NOASSERTION__}}" &&
      return

  [[ -f "${_OSSSCIRrepoResolveDB}" ]] && {
    _ret="$( _dig4repo_hint "${_OSSSCIRrepoResolveDB}" "${1}" )";
    [[ -n "${_ret}" ]] && _say -n " repo hint hit for ${1} " && _gh_sanitize_url "${_ret}" && return;
  }
  _eco="$(cut -d: -f1 <<<"${1}")"
  _scraper_fn="${_eco}_scraper"

  #
  # invoke the scaper function for the eco system passed
  # without the _eco portion of the puri
  #
  [[ -n "$(type -t "${_scraper_fn}")" ]] &&
    [[ "$(type -t "${_scraper_fn}")" = "function" ]] &&
      "${_scraper_fn}" "${1/${_eco}:}" &&
        return
  #
  # other wise a scraper function has not been yet defined
  #

  _gh_sanitize_url "${_ret}"
  return
}

#
# runs ghapi to get project meta data
# "${_pullFN}" "${_pkg}" "${_depout}_deps.json" "${_sbomsrc}"; then
#
pull_ghSBOM()
{
  local _outfile=${2}
  local _sbom_from=${3}
  local _rc=1
  local _code_out
  readonly _outfile
  readonly _sbom_from
  local _retry=${_phy_pkg_api_retry_count}

  [[ ! "${_sbom_from}" =~ github.com  ]] &&
    __xform_sbom_unsupported "${1}" "${_sbom_from}" "sbom API not supported" >"${_depout}_deps.json" && return 0

  _say "running gh api for SBOM from ${_sbom_from} on ${1} to ${_outfile}"
  #
  # do until a success or break after retries
  #
  _code_out="$(mktemp -u -p . -t sbom_http_code.XXXXXXXXXX)"
  while [[ ${_retry} -gt 0 ]] #{
  do
    waitRateLimit "${_lowerLimit}"
    #
    # follow redirects
    # TODO: determine if there are other
    #       places where this needs to be
    #

    curl --location --silent --write-out "%{http_code}" \
      -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${_sbom_from}/dependency-graph/sbom" \
      -o "${_outfile}" > "${_code_out}"

    _rc="${?}"
    read -r _code < "${_code_out}"

    { [[ ${_rc} -gt 0 ]] || [[ ! -s "${_outfile}" ]]; } &&
      _warn --q "${_outfile}: sbom is zero bytes ${_rc} with ${_code}" &&
      _retry=$((_retry-1)) && _say "sleep penalty" && sleep 3

    case "${_code}" in
      "406")
        __xform_sbom_unsupported "${1}" "${_sbom_from}" "sbom not pulled - curl 406 code unrecoverable" > "${_outfile}"
        continue ;;
      "404")
        __xform_sbom_unsupported "${1}" "${_sbom_from}" "sbom not found - likely not enabled on github" > "${_outfile}" ;;
      *)
        ;;
    esac

    [[ ${_rc} -eq 0 ]] && _retry=0
  done #}
  rm -f "${_code_out}"

  #
  # transform sbom to support phylum dependency format (for now)
  #
  grep -q packages "${_outfile}" && mv "${_outfile}" "${_outfile/_deps.json/_ghapi_sbom.json}" &&
     __xform_sbom_prds_dep "${_outfile/_deps.json/_ghapi_sbom.json}" "${_outfile}"

  return ${_rc}
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
_subdepWarningLimit="false"
_dig4subdep()
{
  #
  # this is recursive (but not parallel safe)
  #
  local _lev
  local _c
  local _dep
  local _cmp
  local _r
  local _ftoupdate
  local _depdir
  local _depout
  local _pkg
  local _l
  local _rc
  local _d
  local _sbomsrc

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
  # don't dig past dependencyDepth (-d)
  [[ ${dependencyDepth} != "all" ]] && [[ "${_lev}" -gt ${dependencyDepth} ]] &&
    if "${_subdepWarningLimit}"; then
      _say -n "${_lev}";
      return;
    else
      _info "dependency depth limit '(-d ${dependencyDepth})': skipped deeper dependencies...";
      _subdepWarningLimit="true";
      return;
    fi;

  _cmp="$(_ph_sanitize_cmp "${_c}")"
  _dep="$(cut -d, -f2 <<<"${_cmp}")"

  #
  # TODO/OBE: fix/understand npm dependencies, this algorithm seemingly
  #       goes on forever - just stick to two levels until this is
  #       undertstood
  #       the default TERTIARY_BLACKLIST effectively does this better
  #       users, though, can override this and likely get into a deep search
  #[[ "${_cmp}" =~ ^npm ]] && [ "${_lev}" -eq 2 ] && _warn --q "npm limit: found level ${_lev} skipping ${_cmp} returning..." && return


  # form pkg name, _c, into for needed by
  # phylum.io's API (_pkg) and the naming
  # convention for the subdependent cache
  #
  _pkg="$(makePuri "${_cmp}")"
  _depdir="subdeps.d/$(mkdepdir "${_cmp}")"
  _depout="${_depdir}/$(basename "${_depdir}")"

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

  mkdir -p "${_depdir}"

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
  # if ! pull_phyPackage "${_pkg}" "${_depout}_deps.json"; then
  #
  _pullFN=pull_ghSBOM && [[ "${dependency_type}" == "${__PHYLUM__}" ]] && _pullFN=pull_phyPackage
  #
  # here for SBOM's shortcut the lookup which for non-github srcs will fail
  # TODO: for now the same _c can be id'd as being a dependency in many depths
  #       this grep could results in multiple lines coming back, for for now
  #       only search for relevent github.com hits and ensure only one - not the best
  #
#  _sbomsrc="$(grep --fixed-strings ",${_cmp}," "${_ftoupdate}" | cut -d, -f4 | grep github.com/ | uniq | head -1)"
  _sbomsrc="$(grep --fixed-strings ",${_cmp}," "${_ftoupdate}" | cut -d, -f4 | uniq | head -1)"
  [[ ! "${_sbomsrc}" =~ github.com  ]] &&
    { 
      __xform_sbom_unsupported "${_cmp}" "${_sbomsrc}" "sbom API not supported" >"${_depout}_deps.json" || 
      _warn --q "::::::::: errno $? on '${_depout}_deps.json'"; } &&
      touch "${_depout}_deps.json.err" &&
      touch "${_depout}_deps.json.visited.err" &&
      if ! grep -q --fixed-strings ",${_cmp}," "${_ftoupdate}"; then echo "${_lev},${_cmp},${_dep},unknown,404" >> "${_ftoupdate}"; fi &&
      _say "-n" "&" && return

  [ ! -s "${_depout}_deps.json" ] &&
    _say -n "pulling ${_cmp} dependencies..." &&
    if ! "${_pullFN}" "${_pkg}" "${_depout}_deps.json" "${_sbomsrc}"; then
      [ ! -s "${_depout}_deps.json" ] &&
        _warn "curl failed for ${_cmp}"
      [ -s "${_depout}_deps.json" ] &&
        mv "${_depout}_deps.json" "${_depout}_deps.json.err" &&
        _warn "pull failed for ${_cmp}"

      touch "${_depout}_deps.json.visited.err"
      if ! grep -q --fixed-strings ",${_cmp}," "${_ftoupdate}"; then echo "${_lev},${_cmp},${_dep},unknown,404" >> "${_ftoupdate}"; fi
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
  _r="$(jq -r '.repoUrl|select(.!=null)' "${_depout}_deps.json")"
  [[ -z "${_r}" ]] && _r="${__NOASSERTION__}"
  # if (! grep -q ${id} /etc/passwd) && (! grep ${id} /etc/group); then echo not there; fi
  #
  # short cut to reduce calls to _dig4repo
  # that is only _dig4repo if this pattern is NOT
  # in the file about to be updated the repo is already
  # known (from a # prior run). RISK if repo changed, this'll be wrong
  #
  _line="${_lev},${_cmp},${_dep},github.com/.*/.*,200"
  [[ ! ${_line} =~ ^1, ]] && ! grep -q -o -E "(^${_line}$)" "${_ftoupdate}" &&
  {
    _r=$(_dig4repo "${_cmp}");
    _line="${_lev},${_cmp},${_dep},${_r},200" && { _y="${_line//[^,]}" && [[ ${#_y} -ne 4 ]]; } || { grep -q --fixed-strings ,, <<<"${_line}"; } &&
      _warn "_cmp '${_cmp}' _depout '${_depout}'" && _fatal "corrupt ${_line} pkg being ${_c}";
    if ! grep --fixed-strings -s -q "${_line}" "${_ftoupdate}"; then echo "${_line}" >> "${_ftoupdate}"; fi;
  }

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
      # the dependency (_d) will be sanitized and captured during recursive decent
      # however recording the dependency in the graphviz want the sanitized version
      _line="\"${_cmp}\" -> \"$(_ph_sanitize_cmp "${_d}")\";"
      ! grep --fixed-strings -s -q "${_line}" "${__tmp_dep_graph}" && {
        echo "#s:${_l} ${_d}" >> "${__tmp_dep_graph}" && echo "${_line}" >> "${__tmp_dep_graph}";
      }
      # still need to dig regardless as depth may have changed
      _dig4subdep "${_l}" "${_d}" "${_ftoupdate}"
    done < <(jq -r '.dependencies[]|.id' "${_depout}_deps.json" 2>/dev/null | grep -v -E "(${_TERTIARY_BLACKLIST})" | sort) #}

  touch "${_depout}_deps.json.visited"
  rm -f "${_depout}_deps.json.visiting"
  _say "-n" "x"

  return
}

_phylum_prjId()
{
  local _dolabel="true"
  local _label=""

  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --terse ]] && _dolabel="false"
    shift 1
  done

  local _prj="${1}";
  export _prj;

  "${_dolabel}" && _label="Package URI: "
  [[ "${dependency_type}" == "${__SBOM__}" ]] && "${_dolabel}" && _label="Package ${__SBOM__}: ${dependency_src}, "

  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "${_label}${puri}" && return
  [[ "${dependency_type}" == "${__SBOM__}" ]] && echo "${_label}$(grep SBOM, "${2}" | cut -d, -f3)" && return

  "${_dolabel}" && _label="Phylum Project ID: "

  echo "${_label}$(jq -r '
    .values[] | select(.name==env._prj) |
      [ .name,.id ] | @csv' "${2}" 2>/dev/null | \
    cut -d, -f2 | sed 's/"//g')"
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

  [[ ${dependency_type} == "${__SBOM__}" ]] && jq -r 'if (.sbom) then .sbom else . end|.creationInfo.created' "${dependency_src}" && return
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

  _jobFile="$(mktemp -u -p . -t jobFile.XXXXXXXXXX)"
  _walker_file="$(mktemp -u -p . -t wlkFile.XXXXXXXXXX)"

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
    [[ -d oldjobs ]] && find . -maxdepth 1 -name '*_job_*.json.*' -print0 | xargs -0 -I {} mv {} ./oldjobs/
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

  [[ ${dependency_type} == "${__SBOM__}" ]] && echo "complete" && return
  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "" && return

 _job="$(_phylum_jobId "${1}" "${2}")"
 [[ -z "${_job/,*/}" ]] && _job=null
 { [[ -f "${1}_job_${_job/,*/}.json" ]] && jq -r '.status' "${1}_job_${_job/,*/}.json"; } || echo "";

 return
}

_phylum_jobReport()
{
  local _status
  local _jobUpdated
  local _label="Phylum Job last"

  [[ "${puri}" != "${__NULLPURI__}" ]] && echo "Job Analysis N/A for Package URI (-U)" && return
  [[ "${dependency_type}" == "${__SBOM__}" ]] && _label="${__SBOM__} created on"

  [[ ${1} == --readOnly ]] && _phylum_jobId_BHDT="true" && shift 1

  _jobUpdated="$(_phylum_jobId "${1}" "${2}")"

  _status="$(_phylum_jobStatus "${1}" "${2}")"

  [[ "${_status}" == "incomplete" ]] && _status="${__REDFLAG__}${_status}"

  echo "${_label} ${_jobUpdated/,/ updated at } (${_status})"
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

  "${_debugVerifyCurlJsons}" && { _say -n "Verifying ${1} json...";
  _rc="OK";
  jq -r '.' "${1}" > /dev/null || _fatal "Failed";
  _say "${_rc}";
  }

  return 0
}

#    __phylum_deps "${_apiMethod}" "${_prjid}" "${1}" "${3}"
__phylum_deps()
{
  local _apiMethod="${1}"
  local _prjid="${2}"
  local _cmp="${3}"
  local _file="${4}"

  #
  # TODO: test and warn / error if _prjid cannot be
  #       found - this could be related to a bad
  #       name for the phylum project or a pagination
  #       limit
  _say "getting dependencies of ${_cmp} and _prjid=${_prjid}"

  [ ! -f "${_file}" ] &&
    _say -n "building Phylum project product dependencies caches..." &&
      {
        curl --silent --request GET \
          --url "https://api.phylum.io/api/v0/data/${_apiMethod}/${_prjid}" \
          --header 'accept: application/json' \
          --header "authorization: Bearer $(phylum auth token --bearer)" \
          -o "${_file}" \
        ||
        _fatal "phylum-api project product dependency pre-cache failed.";
      };

  [ ! -f "${_file}" ] || [ ! -s "${_file}" ] &&
    _fatal "${_file} is missing or empty"

  _say "OK"

  [ "$(find "${_file}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${_file} over ${_cache_days}(s) days old, consider rebuilding (-f deps)"

  _patchIfNeeded "${_file}"

  return
}

#  __xform_sbom_unsupported "${_c}" "${_sbomsrc}" "${_msg}"
__xform_sbom_unsupported()
{
  echo "{ \"dependencies\": [], \"_c\": \"${1}\", \"_sbomsrc\": \"${2}\" , \"_msg\": \"${3}\" }";
  return 0
}

#  __xform_sbom_prds_dep "${_sbomsrc}" "${_file}"
__xform_sbom_prds_dep()
{
  local _sbomsrc="${1}"
  local _ofile="${2}"

  while [[ "${1:0:2}" == "--" ]]
  do
    :
    shift 1
  done

  [ ! -f "${_ofile}" ] &&
    jq -r \
    '
     if (.sbom) then .sbom else . end
     | del ( .packages[].externalRefs[]? | select (.referenceCategory!="PACKAGE-MANAGER" ))
     | .packages|=map(.id=.externalRefs[0].referenceLocator)
     | .packages|=map(.repoUrl=null)
     | with_entries(if .key == "packages" then .key = "dependencies" else . end)
    ' "${_sbomsrc}" > "${_ofile}"

  return
}

#    __sbom_deps "${dependency_src}" "${_prjid}" "${1}" "${3}"
__sbom_deps()
{
  local _sbomsrc="${1}"
  local _prjid="${2}"
  local _cmp="${3}"
  local _file="${4}"

  _say "getting dependencies of ${_cmp} and _prjid=${_prjid}"

  jq -r '.' "${_sbomsrc}" > /dev/null || _fatal "${_sbomsrc}: JSON validation Failed:";

  __xform_sbom_prds_dep "${_sbomsrc}" "${_file}"

  [ ! -f "${_file}" ] || [ ! -s "${_file}" ] &&
    _fatal "${_file} is missing or empty"

  _say "OK"

  [ "$(find "${_file}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${_file} over ${_cache_days}(s) days old, consider rebuilding (-f deps)"

  return
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
  local _c
  local _r
  local _dep
  local _cmp

  ${blockNetwork} && _warn "Offline mode, traversing component dependencies, skipped" && return 0

  #########
  # pre-cache phylum project product dependencies
  _say -n "checking ${1} project product dependency caches..."

  ${component_dep_rebuild} || ${force_rebuild} &&
    ! "${_updatingFlag}" && _say -n "forced clearing of product dependency caches..." && rm -f "${3}"

  if [[ "${dependency_type}" == "${__SBOM__}" ]]; then
    _prjid=sbom
    [[ "${dependency_src^^}" == "${__GITHUB__}" ]] && dependency_src="$(grep SBOM, "${__phy_prjs}" | cut -d, -f4)"
    __sbom_deps "${dependency_src}" "${_prjid}" "${1}" "${3}"
  else
    _apiMethod="projects"
    _prjid=$(_phylum_prjId --terse "${1}" "${2}")
    [[ "${puri}" == "${_prjid}" ]] && _apiMethod="packages" && _prjid="$(makePuri "${puri}")"

    [[ -z "${_prjid}" ]] && _fatal "project ${1} not found."
    __phylum_deps "${_apiMethod}" "${_prjid}" "${1}" "${3}"
  fi

  ! "${_updatingFlag}" && _say "resetting ${4}" && cp /dev/null "${4}" && cp /dev/null "${__tmp_dep_graph}" && component_subdep_rebuild="true";

  _say "getting analysis job" && _phylum_jobStatus "${1}" "${3}" 1>/dev/null 2>&1;

    while IFS=$'\t' read -r  _c _r; do #{
      if [ -z "${_c}" ]; then
        break;
      fi

      _cmp="$(_ph_sanitize_cmp "${_c}")"
      _dep="$(cut -d, -f2 <<<"${_cmp}")"

      #
      # record uniq parent/child dependency relationship for graphing
      #
      _line="\"${1}\" -> \"${_cmp}\";"
      ! grep --fixed-strings -s -q "${_line}" "${__tmp_dep_graph}" && {
        echo "#p ${_cmp}" >> "${__tmp_dep_graph}" && echo "${_line}" >> "${__tmp_dep_graph}";
      }

      #
      # short cut to reduce calls to _dig4repo
      # that is if this pattern is in the file about
      # to be updated the github repo is already known (from a
      # prior run). RISK if repo changed, this'll be wrong
      #
      _line="${5},${_cmp},${_dep},github.com/.*/.*,100"
      grep -q -o -E "(^${_line}$)" "${4}" && _say -n "." && continue

      _repo=$(_dig4repo "${_cmp}")
      if [ "${_repo}" == "${__NOASSERTION__}" ] && [ -n "${_r/null/}" ]; then
        _r=${_r//https:\/\//}
        _r=${_r//http:\/\//}
        _repo=$(_dig4repo "${_r}")
      fi
      #
      # keep a list of projects with their repo/vcs home
      #
      _line="${5},${_cmp},${_dep},${_repo},100" && _y="${_line//[^,]}" && [[ ${#_y} -ne 4 ]] && _fatal "corrupt primary line: ${_line} pkg being ${_c}"
      ! grep --fixed-strings -s -q "${_line}" "${4}" && {
        echo "${_line}" >> "${4}";
      }
    done < <(jq -j -r '.dependencies[]|.id,"\t",.repoUrl,"\n"' "${3}" |grep -v -E "(${_PRIMARY_BLACKLIST})")
  return
}

_phylum_subdep_components()
{
  local _prds=${1}
  local _prjs=${2}

  { ${force_rebuild} || ${component_subdep_rebuild}; }  &&
    _say -n "clearing subdep project dependency caches..." && find . \( -name \*visiting -o -name \*visited -o -name \*visited.err \) -delete

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
    while :; do #{
      read -r _c
      if [ -z "${_c}" ]; then
        break;
      fi

      # detect SBOM externalRefs referenceLocator (PACKAGE-MANAGER purl)
      # form is pkg:<type>/<name>@<ver>
      if [[ "${_c}" =~ ^pkg: ]]; then
        _c="$(_ph_sanitize_cmp "${_c}")"
        # this order permits npm:@types... example pattern
        #[[ ${_c} =~ % ]] && _c=$( urldecode "${_c}" )
        # for the project csv, make _c look the same as legacy phylum (for now)
        #   form is <type>:<name>:<ver>
        # Xshellcheck disable=2001
        #_c="$(sed 's^/^:^;s/@\([[:digit:]]\)/:v\1/' <<< "${_c/pkg:}" )"
      fi

      _dig4subdep "${_level}" "${_c}" "${_prjs}"
    done < <( \
      jq -r '.dependencies[]|.id' "${_prds}" | grep -v -E "(${_SECONDARY_BLACKLIST})" | grep -v -E '(^[[:space:]].*$|^$)' \
      | sort) #}

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
    #end scir digraph $(date +%s)
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
__RATELIMIT__="$(mktemp -u -p . -t rateLim.XXXXXXXXXX)"
waitRateLimit()
{
  local _l
  _l="${1}";

  curl -s -u "notUsed:${GITHUB_AUTH_TOKEN}" \
    -I https://api.github.com/user/octocat >"${__RATELIMIT__}" 2>&1
  local _c
  _c=$(grep -i ^x-ratelimit-remaining: "${__RATELIMIT__}"|cut -d: -f2|tr -d '\r')

  #_say l: ${_l}, c: ${_c}
  if [ "${_c}" -le "${_l}" ]; then
    local _r
    local _s
    _r=$(grep ^x-ratelimit-reset: "${__RATELIMIT__}"|cut -d: -f2|tr -d '\r')
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
    _warn "gh api ${_joutput} is incomplete, consider rebuilding (-f cards,meta)"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "gh api ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f cards,meta)"

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

  [[ -s "${_OSSFCS}" ]] && [[ -f "${_OSSFCS}" ]] && [ ! -s "${_joutput}" ] && {
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
    _warn "criticality score ${_joutput} is incomplete, consider rebuilding (-f cards,crit)"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "criticality score ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f cards,crit)"

  return
}

__exec_scard()
{
  local _rc

  _rc=1

  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --alt1 ]]
    shift 1
  done

  if "${_useDocker}"; then
    # _CAStoreDocker needs to word split (SC2086)
    # shellcheck disable=2086
    docker run --rm ${_CAStoreDocker} \
      -e SCORECARD_V6=true \
      -e "GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN}" "${_OSSFSC}" \
      --format=json --show-details \
      --repo="${1}" && _rc=0

  else
    SCORECARD_V6=true "${_OSSFSC}" --format=json --show-details --repo="${1}" && _rc=0
  fi

  return ${_rc}
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

  [ ! -s "${_joutput}" ] &&
    _prjurl="https://github.com/${1}" &&
    _say "running scorecard on ${_prjurl} to ${_joutput}" &&
    waitRateLimit "${_lowerLimit}" &&
    __exec_scard "${_prjurl}" > "${_joutput}" 2> "${_joutput}.err"

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
    _warn "scorecard ${_joutput} is incomplete, consider rebuilding (-f cards,scard)"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "scorecard ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f cards,scard)"

  return
}

__exec_hcheck()
{
  local _altexec
  local _rc

  _rc=1

  _altexec="${_MITRHCquiet}"
  while [[ "${1:0:2}" == "--" ]]
  do
    [[ ${1} == --alt1 ]] && _altexec+=" ${_MITRHCjson}"
    shift 1
  done

  #
  # if running hipcheck natively these two paths will be the same
  # if running hipcheck as a container, these two paths will differ
  #   as such, to do SDN, the .cache/hipcheck folder needs to persist
  #   this, here this ensures the persistent folder exists before the
  #   docker volume is mapped into the container space and is writable
  #   by the container process
  #
  # by doing this the folder ${HOME}/.cache/hipcheck will always have
  # the most recent clone (e.g., 'clones/github') for the SDN search
  #
  [[ ! "${HOME}/.cache/hipcheck" == "${_MITRHCcache}" ]] && {
    mkdir -p "${HOME}/.cache/hipcheck"
    chmod 777 "${HOME}/.cache/hipcheck"
  }
  if "${_useDocker}"; then
    # _CAStoreDocker, __MITRHCquiet, _MITRHCrepoCmd, _MITRHCjson need to word split (SC2086)
    # shellcheck disable=2086
    docker run --rm ${_CAStoreDocker} \
      -v "${_MITRHCconfig}:/app/config" \
      -v "${_MITRHCscripts}:/app/scripts" \
      -v "${HOME}/.cache/hipcheck:${_MITRHCcache}" \
      -e "HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN}" "${_MITRHC}" \
      ${_altexec} \
      ${_MITRHCrepoCmd} "${1}" && _rc=0
  else
    # shellcheck disable=2086
    HC_GITHUB_TOKEN="${GITHUB_AUTH_TOKEN}" "${_MITRHC}" --config "${_MITRHCconfig}" ${_altexec} ${_MITRHCrepoCmd} "${1}" && _rc=0
  fi

  return ${_rc}
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

  [ ! -s "${_joutput}" ] && {
    _say "running hipcheck on ${_prjurl} to ${_joutput}"
    waitRateLimit "${_lowerLimit}" && {
    __exec_hcheck --alt1 "${_prjurl}" > "${_joutput}" 2> "${_toutput}" ||
      {
        grep -q -E '"recommendation":' "${_joutput}" ||
        {
          _warn "hipcheck ${_toutput} failed, see file for hints"
          mv "${_joutput}" "${_joutput}".err
          return
        }
      };
    }

    #
    # got here so hc.json is likely good
    # don't need the .err file at this point
    #
    [[ -s "${_joutput}" ]]
      rm -f "${_joutput}".err
    #
    # in later versions of hipcheck there are errors reported by
    # plugins which are really informational given that a message
    # later appears in the JSON errored struct that repeats that
    # same problem, ignore these for now
    #
    sed -i '/ERROR plugin::/d' "${_toutput}"

   if ver_between 0 "${_mitre_hipcheck_ver}" "${_MITRHCnewSchemaVersion}"; then
    waitRateLimit "${_lowerLimit}" &&
    __exec_hcheck "${_prjurl}" > "${_toutput}" 2>&1 &&
      {
        grep -E risk\ rated "${_toutput}" >/dev/null ||
        {
          _warn "hipcheck ${_toutput} failed, see file for hints" &&
          return
        }
        head -n -2 "${_joutput}" ;
        b64=$(base64 -w 0 "${_toutput}") ;
        echo '  },';
        echo -n '  "rationale": "' ; echo -n "${b64}";
        echo '"'; echo -n '}'
      } > "${_joutput}.tmp" &&
      mv "${_joutput}.tmp" "${_joutput}" &&
      if jq -r '.' "${_joutput}" > /dev/null 2>&1; then rm "${_toutput}"; fi &&
      [ -s "${_toutput}" ] && _warn "json filter error, ${_toutput} not deleted"
   fi
  }

  [ ! -s "${_joutput}" ] &&
    _warn "hipcheck ${_joutput} is incomplete, consider rebuilding (-f cards,hcheck)" &&
    [ -s "${_toutput}" ] &&
    _warn "hipcheck ${_toutput} failed, see file for hints"

  [ "$(find "${_joutput}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "hipcheck ${_joutput} over ${_cache_days}(s) days old, consider rebuilding (-f cards,hcheck)"

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
      SanctionedAuthor)
        # computed in detect_sdn
        # can't do this here (yet)
        #detect_sdn "${__sdnDB}" "${__ghrcommitjson}"
        MYcheckScores["${check}"]="${#SDNhits[@]}"
        ;;
      *)
        ;;
    esac
  done

  #_say -n "running plugins..."
  _run_scir_plugins "${component}" "$(basename "${gh_site}")" "" ""
  #_say OK
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
  local _nameMatch

  _containerTimeout="${2}"
  _PIDtty="${3}"
  _politePolice=5

  #
  # want this for synchronization
  #
  read -r _scoreRunnerPID

  # likely unneccessary but harmless double check
  [[ "${_scoreRunnerPID}" != "${1}" ]] &&
    _warn "_scoreRunnerPID != ${1}" &&
    return 1

  _scoreRunnerPID="${1}"

  # do this as long as our parent/grandparent is around (no zombies)
  while [[ -d /proc/${_scoreRunnerPID} ]]
  do
    # honor parent/grandparent job control (STOP|CONT)
    grep State "/proc/${_scoreRunnerPID}/status" |grep -q stopped && sleep "${_politePolice}" && _say "${_scoreRunnerPID} PAUSED" && continue

  if "${_useDocker}"; then
    # only track containers matching our parent process ID
    _containerPID=$(pgrep -a -P "${_scoreRunnerPID}" -f "docker run" | grep _TOKEN | awk '{ print $1 }')
  else
    # only track scorecard or hc (hipcheck) matching our parent process ID
    _containerPID=$(pgrep -a -P "${_scoreRunnerPID}" "(scorecard|hc)" | awk '{ print $1 }')
  fi
    [[ -z "${_containerPID}" ]] && sleep "${_politePolice}" && continue

  if "${_useDocker}"; then
    #
    # TODO: not sure if possible, grab the right container
    #       if this returns more than one running container
    #
    _containerCID="$(docker ps |grep -v STATUS |awk '{ print $1 }')"
    [[ -z "${_containerCID}" ]] && sleep "${_politePolice}" && continue
    _nameMatch="(scorecard|hipcheck)"
    _say "watching PID=${_containerPID} ($(tr '\0' ' ' <"/proc/${_containerPID}/cmdline" | grep -o -E "${_nameMatch}" | head -1)), CONTAINER=${_containerCID} on ${_PIDtty/not a tty/no tty} not to exceed ${_containerTimeout} seconds"
  else
    _nameMatch="(scorecard|hipcheck|hc)"
    _say "watching PID=${_containerPID} ($(tr '\0' ' ' <"/proc/${_containerPID}/cmdline" | sed 's^[[:space:]].*^^g;s/.*\///' | grep -o -E "${_nameMatch}" | head -1)), on ${_PIDtty/not a tty/no tty} not to exceed ${_containerTimeout} seconds"
  fi
    # have a thing to watch
    _start="${EPOCHSECONDS}"

    while [[ -d /proc/${_containerPID} ]]
    do
      [[ $(( EPOCHSECONDS - _start )) -ge _containerTimeout ]] &&
        _warn "killed ${_containerPID}/${_containerCID}: working on $(tr '\0' ' ' <"/proc/${_containerPID}/cmdline" | sed 's/ghp_[[:alnum:]]*/ghp_\(redacted\)/g')" &&
  if "${_useDocker}"; then
        docker kill "${_containerCID}"
  else
        # hipcheck uses child processes for parallel analyzes
        pkill -TERM -P "${_containerPID}"
        # pkill (here) does not kill the parent
        kill -TERM "${_containerPID}"
  fi
      sleep "${_politePolice}"
      grep State "/proc/${_scoreRunnerPID}/status" |grep -q stopped && _say "${_scoreRunnerPID} PAUSED breaking" && break
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

    _info "Policing for potentially stalled scoring containers on ${_mytty/\/dev\/} (see: -W to change)" ;
  }

    while :; do #{
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
    done < <(grep -E "${_seq}" "${2}" \
    | cut -d, -f4 \
    | grep github \
    | sed  's^HTTPS://^^gi;s^\.git^^gi'  \
    | cut -d/ -f2,3 \
    | sort \
    | uniq) #}

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
    _say "done policing for potentially stalled scoring containers on ${_mytty/\/dev\/}";
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
     _warn "scorecard ${_joutput} failed, consider rebuilding (-f scores)" &&
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
      #
      # a valid hipcheck file has 2 structures if early scheme
      # otherwise it only has 1 structure we're searching for
      #
      [ "$(jq -r '.recommendation.kind' "${_joutput}")" == "null" ] ||
      {
      ! grep -s -q -E '(policy_expr)' "${_joutput}" &&
      [ "$(jq -r '.rationale' "${_joutput}")" == "null" ];
      }
    } &&
    _warn "hipcheck ${_joutput} failed, consider rebuilding (-f scores)"

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

    while :; do #{
      read -r _OwnerRepo

      [ -z "${_OwnerRepo}" ] && break

      [ "${_OwnerRepo}" = "${__NULLGH__}" ] && continue

      _say -n "+"
      _localdepdir="deps.d/$(mkdepdir "${_OwnerRepo}")"
      mkdir -p "${_localdepdir}"

      _val_scorecard "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}"
      _val_hipcheck "${_OwnerRepo}" "$(basename "${_localdepdir}")" "${_localdepdir}"

    done < <(grep -E "${_seq}" "${1}" \
    | cut -d, -f4 \
    | grep github\
    | sed  's^HTTPS://^^gi;s^\.git^^gi' \
    | cut -d/ -f2,3\
    | sort \
    | uniq) #}

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

      { [ ! -s "${_SCinput}" ] || [ ! -s "${_HCinput}" ] || \
        ! jq -r '.' "${_SCinput}" || ! jq -r '.' "${_HCinput}"; } 1>/dev/null 2>&1 && _missingJson=$((_missingJson+1)) && continue

      # CSV header (do once)
      # 3 parts to coalesce
      # part 1, first column, Component name (first echo -n)
      # part 2, next 18 cols, from scorecard (second echo -n)
      # part 3, last 9 cols, from hipcheck (third echo -n)
      #
      # word splitting is necessary for sort to work properly
      # shellcheck disable=2046
      ${coalesce_header} &&
        {
          echo -n "Component," &&
          echo -n $(jq -r '.checks[]|[ .name,.score ] | @csv' "${_SCinput}" | sort | cut -d, -f1 | sed 's/^"//g;s/"$/,/g') | sed 's/, /,/g;s/,$//g' && echo -n "," &&
          echo -n $( (jq -r '.passing[]| [.analysis,.value ]|@csv' "${_HCinput}"; jq -r '.failing[]| [.analysis,.value ]|@csv' "${_HCinput}";  jq -r '.errored[]| [.analysis,"-1"]|@csv' "${_HCinput}") | sort | cut -d, -f1 | sed 's/^"//g;s/"$/,/g' | sed 's/, /,/g;s/,$//g') | sed 's/ /,/g' &&
          echo ""
        } > "${3}" &&
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
      {
        echo -n "$(basename "${_localdepdir}"),"
        echo -n $(jq -r '.checks[]|[ .name,.score ] | @csv' "${_SCinput}" | sort | cut -d, -f2 | sed 's/^"//g;s/"$/,/g') | sed 's/ /,/g;s/,$//g'
        echo -n ","
        if [ -s "${_HCinput}" ]; then
          echo -n $( (jq -r '.passing[]| [.analysis,.value ]|@csv' "${_HCinput}"; jq -r '.failing[]| [.analysis,.value ]|@csv' "${_HCinput}";  jq -r '.errored[]| [.analysis,"-1"]|@csv' "${_HCinput}") | sort | cut -d, -f2 | sed 's/^"//g;s/"$/,/g' | sed 's/, /,/g;s/,$//g') | sed 's/ /,/g'
        else
          echo -n "-1,-1,-1,-1,-1,-1,-1,-1,-1"
        fi
        echo ""
       } >> "${3}"

  done < <( \
    cut -d, -f4 "${2}" \
    | grep github | sed  's^HTTPS://^^gi;s^\.git^^gi' | cut -d/ -f2,3 \
    | sort | uniq) #}

  _say ""
  [ "${_missingJson}" -gt "0" ] && _warn "coalesce_scorecards: counted ${_missingJson} missing or corrupt project scorecard(s)"
  [ ! -s "${3}" ] && _warn "coalesce_scorecards: no scores from scorecard or hipcheck found." && cp /dev/null "${3}"
  return
}

build_sdn()
{
  local _sdnWebsitesUpdated
  local _metainfo
  local _lastUpdate
  local _csvinfo

  local _sdnType
  local _programList
  local _lastName
  local _uid
  local _lookups
  local _urlSrc

  # get date of latest SDN ingest
  _sdnWebsitesUpdated="$(curl -L --silent -X 'GET'   'https://sanctionslistservice.ofac.treas.gov/changes/latest'   -H 'accept: */*' -o - | grep '<datePublished>' | sed 's^<[/]*datePublished>^^g;s/[[:space:]]*//g;s/T[[:digit:]:-]*//g')"
  [[ -z "${_sdnWebsitesUpdated}" ]] && _warn "cannot get last SDN update date" && return 1
  _sdnWebsitesUpdated="$(date -d "${_sdnWebsitesUpdated}" +%s)"

  _metainfo="$(dirname "${1}")/sdn.meta.txt"
  [[ ! -f "${_metainfo}" ]] && echo "${_sdnWebsitesUpdated}" > "${_metainfo}"

  _lastUpdate=$(<"${_metainfo}")

  ${protectNoUpdate} && { [[ ! -f "${1}" ]] || [[ "${_sdnWebsitesUpdated}" -gt "${_lastUpdate}" ]]; } &&
    _warn "OFAC Update available but updates are disabled (see -p)" && return 0

  ! ${protectNoUpdate} && { [[ ! -f "${1}" ]] || [[ "${_sdnWebsitesUpdated}" -gt "${_lastUpdate}" ]]; } && {
    _csvinfo="$(mktemp -u -p . -t csvF.XXXXXXXXXX)" && cp /dev/null "${_csvinfo}"
    #
    # TODO: confirm File signature (need to scrape off the download html page)
    #
    _urlSrc="https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/SDN.CSV"
    curl -L --silent -X 'GET' "${_urlSrc}" -H 'accept: */*' -o "${_csvinfo}"
    echo "${_sdnWebsitesUpdated}" > "${_metainfo}"
    cat <<-_SDNHDR > "${1}"
{
  "version": "IOC 1.0",
  "urlSrc": "${_urlSrc}",
  "metaInfo": "${_metainfo}",
  "lastUpdated": "${_sdnWebsitesUpdated}",
  "emails": [
_SDNHDR
    while IFS= read -r _email
    do
    #
    # there can be multiple entries in the csv that
    # could have a _email hit, here we use the _email
    # as the primary key, here relevent information
    # is consolidated in those cases
    #
    _uid="$(grep -i "${_email}" "${_csvinfo}"         | csvtool col 1 -| tr '\n' '|'| sed 's/|$//g;s/|/ \(and\) /g;s/"//g')"
    _lastName="$(grep -i "${_email}" "${_csvinfo}"    | csvtool col 2 -| tr '\n' '|'| sed 's/|$//g;s/|/ \(and\) /g;s/"//g')"
    _sdnType="$(grep -i "${_email}" "${_csvinfo}"     | csvtool col 3 -| sed 's/-0-/entity/g'| tr '\n' '|'| sed 's/|$//g;s/|/ \(and\) /g')"
    _programList="$(grep -i "${_email}" "${_csvinfo}" | csvtool col 4 -| tr '\n' '|'| sed 's/|$//g;s/|/ \(and\) /g;s/"//g')"
    _lookups="$(grep -i "${_email}" "${_csvinfo}"     | csvtool -u '|' col 1-2 - | { while IFS='|' read -r _xuid _xlastName; do echo "{"; echo \"uid\": \""${_xuid}"\",; echo \"lastName\": \""${_xlastName}"\"; echo "}"; done; } | jq -r --slurp 'map("["+.uid+"](https://sanctionssearch.ofac.treas.gov/Details.aspx?id="+.uid+") " + .lastName)' )"
    cat <<-_SDNENT >> "${1}"
    {
      "email_addr": "${_email}",
      "source": "SDN",
      "confidence": "critical",
      "reason": "",
      "uid": "${_uid}",
      "lastName": "${_lastName}",
      "sdnType": "${_sdnType}",
      "programList": "${_programList}",
      "lookups": ${_lookups}
    },
_SDNENT
    done < <(grep -o -E "[a-zA-Z0-9._%±]+@[a-zA-Z0-9.-]+.[a-zA-Z]{2,}" "${_csvinfo}" | sort | uniq)
    cat <<-_SDNFTR >> "${1}"
    {
      "email_addr": "zzzdummyxxx",
      "source": "SDN",
      "confidence": "low",
      "reason": "",
      "uid": "0",
      "lastName": "",
      "sdnType": "entity",
      "programList": "none",
      "lookups": [ ]
    }
  ]
}
_SDNFTR
  }

  ! jq -r '.' "${1}" >/dev/null && _warn "jq failed on ${1}" && return 1

  rm -f "${_csvinfo}"
  _sdnlist_ver="$(date -d@"$(<"${_metainfo}")" +%Y-%m-%d)"

  return 0
}

detect_sdn()
{
  local _cwd
  local _hcache
  local _committer
  local _repo

  _cwd="$(realpath "${PWD}")"
  _hcache="${_MITRHCcache}"
  ${_useDocker} && _hcache="${HOME}/.cache/hipcheck"
  _say -n "collecting git contributors..."
  cp /dev/null "${_cwd}/${__gitcontribcsv}.tmp"
  cp /dev/null "${__gitcontribcsv/contrib/unk_contrib}.tmp"
  #
  # for every github/repo site for which hipcheck was
  # run, there should be a git clone where committer
  # email addresses can be harvested, do that here
  #
  while IFS= read -r _x
  do
    _sdnDir="$(basename "$(dirname "${_x}")"|sed 's/___/\//g')";
    { pushd "${_hcache}/clones/github/${_sdnDir}" >/dev/null 2>&1; } || { _warn "cannot identify committers to ${_sdnDir}" && continue; }

    #
    # subtle note: without "HEAD", shortlog will test if
    # stdin isatty(0) and will fail if container is NOT
    # running with interactive flag (-it), so need to
    # specify HEAD to keep this from failing.
    { while IFS= read -r _committer
    do
      echo "${_sdnDir},${_committer//[<>]/}"
    done < <(git shortlog -sne HEAD | grep -o -E '<[() [:alnum:]].*@[[:alnum:]].*>'); } >> "${_cwd}/${__gitcontribcsv}.tmp"

    { while IFS= read -r _committer
    do
      echo "${_sdnDir},${_committer//[<>]/}"
    done < <(git shortlog -sne HEAD | grep -v -o -E '<[() [:alnum:]].*@[[:alnum:]].*>'); } >> "${_cwd}/${__gitcontribcsv/contrib/unk_contrib}.tmp"

    popd > /dev/null || cd "${_cwd}" || break
  done < <(find . ! -size 0 -type f -iname \*hc.json);

  ! cmp -s "${__gitcontribcsv}.tmp" "${__gitcontribcsv}" && \
      mv "${__gitcontribcsv}.tmp" "${__gitcontribcsv}"
  ! cmp -s "${__gitcontribcsv/contrib/unk_contrib}.tmp" "${__gitcontribcsv/contrib/unk_contrib}" && \
      mv "${__gitcontribcsv/contrib/unk_contrib}.tmp" "${__gitcontribcsv/contrib/unk_contrib}"
  rm -f "${__gitcontribcsv}.tmp" "${__gitcontribcsv/contrib/unk_contrib}.tmp"

  #
  # IFF there are newer known contributors - force issues update using BFLAGS
  #
  [[ "${__gitcontribcsv}" -nt "${component}_allIssues.json" ]] && _say "detected contributor change, rebuilding issues" && BFLAGS[issues]=true

  _say "OK"

  [[ ! -f "${1}" ]] && _warn "no OFAC SDN cached, cannot detect SDNs" && return 0

  _say -n "detecting SDN from collected contributors..."
  while IFS=, read -r _repo _committer
  do
    #
    # if there is a quicklook hit then
    # incur the overhead of pulling the record
    #
    grep -q -i "${_committer}" "${1}" && \
      SDNhits["${_repo},${_committer}"]="$(jq -r --arg RP "${_repo}" --arg EM "${_committer}" \
        '.emails[] |
           select((.email_addr|ascii_upcase) == ($EM|ascii_upcase)) |
           . += { "committer":$EM, "repo":$RP }' "${1}")"
  done < "${__gitcontribcsv}"

  _say "OK"

  return 0
}

_sdnactors()
{
  local _msg
#  echo "${SDNhits[@]}" | tr -d '\n' | sed 's/"/|/g'

  _msg=", no sanctioned author(s) detected."
  [[ ${MYcheckScores[SanctionedAuthor]} -gt ${MYcheckThresholds[SanctionedAuthor]} ]] && _msg=", detected sanctioned author(s) $( jq -r '.|[.committer, .repo]|join(",")' <<<"${SDNhits[@]}"|tr '\n' ';'|sed 's/;/; /g'|sed 's/; $//g' )"
  echo "$(_fotp "${MYcheckScores[SanctionedAuthor]}" "${MYcheckThresholds[SanctionedAuthor]}" "gt")${MYcheckScores[SanctionedAuthor]}/${MYcheckThresholds[SanctionedAuthor]}${_msg}"

  return 0
}

_phy_prj_cache()
{
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
      {
        curl --silent --request GET \
          --url 'https://api.phylum.io/api/v0/projects/?paginate.limit=100' \
          --header 'accept: application/json' \
          --header "authorization: Bearer $(phylum auth token --bearer)" \
          -o "${__phy_prjs}" \
      ||
        _fatal "phylum-api project pre-cache failed.";
      };

  [ ! -f "${__phy_prjs}" ] || [ ! -s "${__phy_prjs}" ] &&
    _fatal "${__phy_prjs} is missing or empty"

  _say "OK"

  [ "$(find "${__phy_prjs}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__phy_prjs} over ${_cache_days}(s) days old, consider rebuilding (-f caches)"

  return
}

#
# builds frequently referenced (json) data sources
# for a phylum project and its GitHub counterparts
# helps to reduce the GitHub rateLimit enforements
#
build_caches()
{
  local _htcode
  ${blockNetwork} && _warn "Offline mode, cache updates, skipped" && return 0

  #########
  # pre-cache github site html which may have badge information
  _say -n "checking GH html..."

  if ${BFLAGS[caches]} || ${force_rebuild} || grep -s -q Bad\ credentials "${__ghhtml}"; then
    _say -n "forced clearing GH html..."
    rm -f "${__ghhtml}"
  fi
  #
  # if this exists from a prior
  # run - remove it now as likely
  # no needed
  #
  rm -f "${__ghhtml}.NG"

  ${__ghSKIP} && echo "<html></html>" > "${__ghhtml}"

  [ ! -f "${__ghhtml}" ] && _say -n "building GH html..." &&
    {
      _htcode="$(curl --silent --write-out "%{http_code}" \
        -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${__gh}" \
        -o "${__ghhtml}")" \
    ||
      _fatal "gh html pre-cache failed.";
    };

  [ ! -f "${__ghhtml}" ] || [ ! -s "${__ghhtml}" ] || [[ "${_htcode}" =~ ^4[[:digit:]]{2} ]] &&
    _info "$(mv -v -f "${__ghhtml}" "${__ghhtml}.NG")" &&
    _fatal "${__gh} was not accessible (see -G parameter and access rights, (${_htcode}))"

  if grep -q Bad\ credentials "${__ghhtml}"; then _fatal "${__ghhtml} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghhtml}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghhtml} over ${_cache_days}(s) days old, consider rebuilding (-f caches)"

  #########
  # pre-cache api.github
  _say -n "checking GH caches..."

  if ${BFLAGS[caches]} || ${force_rebuild} || grep -s -q Bad\ credentials "${__ghrjson}"; then
    _say -n "forced clearing GH caches..."
    rm -f "${__ghrjson}"
  fi

  ${__ghSKIP} && echo "{ }" > "${__ghrjson}"

  [ ! -f "${__ghrjson}" ] && _say -n "building GH caches..." &&
    {
      curl --silent \
        -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${__ghr}" \
        -o "${__ghrjson}" \
    ||
      _fatal "gh-api pre-cache failed.";
    };

  [ ! -f "${__ghrjson}" ] || [ ! -s "${__ghrjson}" ] &&
    _fatal "${__ghrjson} is missing or empty"

  if grep -q Bad\ credentials "${__ghrjson}"; then _fatal "${__ghrjson} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghrjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrjson} over ${_cache_days}(s) days old, consider rebuilding (-f caches)"

  #########
  # pre-cache countribor counts from api.github
  _say -n "checking GH contributor caches..."

  #${force_rebuild} &&
  if ${BFLAGS[caches]} || ${force_rebuild} || grep -q Bad\ credentials "${__ghrjson}"; then
    _say -n "forced clearing GH credential and commit caches..."
    rm -f "${__ghrcontribjson}" "${__ghrcommitjson}"
  fi

  ${__ghSKIP} && echo "{ }" > "${__ghrcontribjson}"

  [ ! -f "${__ghrcontribjson}" ] &&
    _say -n "building GH contributor and commit caches..." &&
      {
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
          done >> "${__ghrcontribjson}" \
       ||
       _fatal "gh-api contrib pre-cache failed.";

        cp /dev/null "${__ghrcommitjson}"
        #
        # do no more than the last 100 commits (a choice not a limit)
        # shellcheck disable=SC2043
        for pg in 1
          do
             curl --silent \
               -H "Accept: application/vnd.github+json" \
               -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
               "${__ghr}/commits?per_page=100&page=${pg}"
          done >> "${__ghrcommitjson}" \
       ||
       _fatal "gh-api commit pre-cache failed.";
      };

  [ ! -f "${__ghrcontribjson}" ] &&
    _fatal "${__ghrcontribjson} is missing or empty"

  if grep -q Bad\ credentials "${__ghrcontribjson}"; then _fatal "${__ghrcontribjson} bad GITHUB_AUTH_TOKEN credentials"; fi

  [ ! -f "${__ghrcommitjson}" ] &&
    _fatal "${__ghrcommitjson} is missing or empty"

  if grep -q Bad\ credentials "${__ghrcommitjson}"; then _fatal "${__ghrcommitjson} bad GITHUB_AUTH_TOKEN credentials"; fi

  _say "OK"

  [ "$(find "${__ghrcontribjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrcontribjson} over ${_cache_days}(s) days old, consider rebuilding (-f caches)"

  [ "$(find "${__ghrcommitjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrcommitjson} over ${_cache_days}(s) days old, consider rebuilding (-f caches)"

  #########
  # pre-cache SBOM
  _say -n "checking GH SBOM caches..."

  if ${BFLAGS[caches]} || ${force_rebuild} || grep -q Bad\ credentials "${__ghrjson}"; then
    _say -n "forced clearing GH SBOM caches..."
    rm -f "${__ghrsbomjson}"
  fi

  ${__ghSKIP} && echo "{ }" > "${__ghrsbomjson}"

  [ ! -f "${__ghrsbomjson}" ] && _say -n "building GH SBOM caches..." &&
    {
      curl --location --silent --write-out "%{http_code}" \
        -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${__ghr}/dependency-graph/sbom" \
        -o "${__ghrsbomjson}" >/dev/null \
     ||
      _fatal "gh-api SBOM pre-cache failed ${?}.";
    };

  #
  # these conditions are only fatal if the gh sbom
  # is the source for all dependencies (-P github:sbom)
  # otherwise a user supplied SBOM is necessary
  #
  if [[ "${dependency_src}" == "${__ghrsbomjson}" ]]; then
    { ! jq -r '.' "${__ghrsbomjson}" > /dev/null || [ ! -f "${__ghrsbomjson}" ] || [ ! -s "${__ghrsbomjson}" ]; } &&
      _fatal "${__ghrsbomjson} is corrupt, missing or empty"

    grep -q Bad\ credentials "${__ghrsbomjson}" && _fatal "${__ghrsbomjson} bad GITHUB_AUTH_TOKEN credentials"

    grep -q -E '("status": "404")' "${__ghrsbomjson}" && _fatal "github dependency graph disabled for ${component}, please supply an SBOM using <jsonfile>:sbom (see -P)"
  fi

  _say "OK"

  [ "$(find "${__ghrsbomjson}" -mtime +"${_cache_days}" -print 2>/dev/null)" ] &&
    _warn "${__ghrsbomjson} over ${_cache_days}(s) days old, consider rebuilding (-f caches)"

  #########
  #
  [[ "${dependency_type}" == "${__SBOM__}" ]] && {
    # in lieu of _sbom_prj_cache as this SBOM is the only project for this component
    if [[ "${dependency_src^^}" == "${__GITHUB__}" ]]; then
      echo "${dependency_type},${__ghrsbomjson},$(md5sum "${__ghrsbomjson}" | sed 's/  /,/')" > "${__phy_prjs}"
      dependency_src="${__ghrsbomjson}"
    else
      echo "${dependency_type},${dependency_src},$(md5sum "${dependency_src}" | sed 's/  /,/')" > "${__phy_prjs}"
    fi
  }

  #########
  # pre-cache SDN
  if ${BFLAGS[caches]} || ${force_rebuild} ; then
    _say -n "forced clearing OFAC SDN caches..."
    rm -f "${__sdnDB}"
  fi

  _rc=1
  #
  # building the sdn cache ensures it is up to date no
  # need to check for aging against _cache_days
  #
  _say -n "checking OFAC SDN caches..." && build_sdn "${__sdnDB}" && _rc=0
  { [[ ${_rc} -eq 1 ]] && _fatal "${__sdnDB} is corrupt, missing or empty"; } || { _say "OK"; }

  #########
  # pre-cache phylum projects
  [[ "${dependency_type}" == "${__PHYLUM__}" ]] && {
    _phy_prj_cache
  }

  #########
  # pre-cache for plugins
  _say -n "checking plugin caches..."
  _cache_scir_plugins
  _say OK

  return
}

_mk_grype_xform_pipeline()
{
cat <<-_GYXPIPELINEEOF > "${1}"
jq -r 'if (.sbom) then .sbom else . end' "\${1}"| ${_GRYPEC} -o json | jq -r '
.matches[]? |
{
  "title":(.artifact.purl+" version "+.matchDetails[0].found.versionConstraint),
  "tag":((if (.vulnerability.severity?)
          then
            (if .vulnerability.severity | ascii_downcase == "critical" then "CV-"
             elif .vulnerability.severity | ascii_downcase == "high" then "HV-"
             elif .vulnerability.severity | ascii_downcase == "medium" then "MV-"
             else "LV-" end)
          else "UN-" end)+
          .vulnerability.id),
  "id":.artifact.purl,
  "severity":( if (.vulnerability.severity?) then .vulnerability.severity | ascii_downcase else "Not Provided" end ),
  "description":(
          "### Overview\n\n"+(.vulnerability.description // "None Provided")+":__BR__:**Grype Data Source**: "+(.vulnerability.dataSource // "None Provided")+
           "\n\n### Recommendation\n\nFix available in "+(if (.vulnerability.fix.versions|length > 0) then .vulnerability.fix.versions|join(", ") else "None Provided" end)+
           "\n\n### References\n\n"+(if (.relatedVulnerabilities|length > 0) then .relatedVulnerabilities[].urls|join(":__BR__:") else "None Provided" end // "NO URL")+
           "\n\n**CVE**: "+
           ((if ((.vulnerability.id) and (.vulnerability.id | startswith ("CVE"))) then .vulnerability.id
             else .relatedVulnerabilities[0].id // "None Provided" end))+
             " - **CVSS**: "+(.vulnerability.cvss[0]?.metrics.baseScore|tostring)+
             "\n"
         ),
  "details": {
  "type":"vulnerability",
  "cvss":.vulnerability.cvss[0]?.metrics.baseScore,
  "cvss_vector":(if (.vulnerability.cvss|length >0) then [ .vulnerability.cvss[].vector ] | @csv
                 else "None Provided" end)
    },
  "domain":"vulnerability",
  "impact":( if (.vulnerability.severity?) then .vulnerability.severity | ascii_downcase else "Not Provided" end ),
  "riskType":"vulnerabilities"
}
'
_GYXPIPELINEEOF

  return 0
}

#
# runs grype on sbom files and transforms the generated
# grype results to a json report format for scir-oss report
#
# \*_sbom.json --> \*_sbom_grype.json
#
# TODO: make this unify all \*_sbom.json files into a
#       comprehensive grype report
#
grype_issues()
{
  local _seq
  local _cmp
  local _c
  local _depdir
  local __gyxform
  local __gxpipeLine
  local __rootSBOM

  #
  # operates like scorecards, runs off levels in prjs.csv
  #
  _seq='^[0-9]+,'
  { [[ ${issueDepth} != "all" ]] && [[ ${issueDepth} != "auto" ]] ; } && _seq="^($(seq --separator='|' 0 "${issueDepth}")),"

  # ^0, is special - always do it it's SBOM is known
  IFS="," read -r _c __rootSBOM _m _o < "${__phy_prjs}"; unset _m _o
  ! { [[ "${_c}" == "SBOM" ]] && [[ -s "${__rootSBOM}" ]]; } && _debug "no root SBOM for grype issues" && return

  __gyxform=$(mktemp -u -p . -t gyxF.XXXXXXXXXX) && cp /dev/null "${__gyxform}"

  __gxpipeLine="$(mktemp -u -p . -t gyxP.XXXXXXXXXX)"
  _mk_grype_xform_pipeline "${__gxpipeLine}"

  _say -n "running ${_GRYPEC} scan for ${1} from ${2} to level ${issueDepth}..."

  # does the _sbom_grype need to be built
  { [[ "${__rootSBOM}" -nt "${1}_allIssues.json" ]] || [[ ! -s "${1}_sbom_grype.json" ]] ; } &&
    bash "${__gxpipeLine}" "${__rootSBOM}" > "${__gyxform}" && _say -n "$(grep -c \"tag "${__gyxform}")"

  while read -r _cmp;
  do
    _c="$(mkdepdir "${_cmp}")"
    _depdir="subdeps.d/${_c}"
    [[ ! -d "${_depdir}" ]] && _depdir="deps.d/${_c}" && [[ ! -d "${_depdir}" ]] && continue
    [[ ! -f "${_depdir}/${_c}_ghapi_sbom.json" ]] && continue
    # does the _sbom_grype need to be built
    { [[ "${_depdir}/${_c}_ghapi_sbom.json" -nt "${1}_allIssues.json" ]] ; } &&
      bash "${__gxpipeLine}" "${_depdir}/${_c}_ghapi_sbom.json" >> "${__gyxform}" &&
      _say -n "." && continue
    _say -n "^"
  done < <(grep -E "${_seq}" "${2}" \
          | grep github.com \
          | cut -d, -f2)

  mv "${__gyxform}" "${1}_sbom_grype.json"
  rm -f "${__gxpipeLine}"

  _say "$(grep -c \"tag "${1}_sbom_grype.json"), OK"

  return 0
}

consolidate_issues()
{
  local __grepo
  local __lic
  local _liseq
  local _site
  local _id
  local __ghapiFiles
  local __phdepFiles
  local __grypeFiles

  cp /dev/null "${3}"

  # do only if grype is installed
  [[ ! ${_grype_ver} == "${__NOASSERTION__}" ]] && {
    { ${BFLAGS[issues]} || ${force_rebuild} ; } && cp /dev/null "${2}_sbom_grype.json"

    grype_issues "${2}" "${4}"
  }

  #
  # speedup
  #
  _say -n "gather issue files..."
  __ghapiFiles=$(mktemp -u -p . -t ghapi.XXXXXXXXXX) &&
    find . -name \*_ghapi.json -print0 > "${__ghapiFiles}"

  ! grep -q ^SBOM, "${__phy_prjs}" && { _say -n " ..."
    __phdepFiles=$(mktemp -u -p . -t phdep.XXXXXXXXXX)
      find . \( -name \*_dep_prds.json -o -name \*deps.json \) -print0 > "${__phdepFiles}"; }

  [[ ! ${_grype_ver} == "${__NOASSERTION__}" ]] && { _say -n " ..."
    __grypeFiles=$(mktemp -u -p . -t grype.XXXXXXXXXX) &&
      find . \( -name \*_sbom_grype.json \) -print0 > "${__grypeFiles}"
  }
  _say "OK"


  for __risk__ in "vulnerabilities" "maliciousCodeRisk" "engineeringRisk" "licenseRisk" "authorsRisk"
  do #{
    #
    # ran into an instance when the _dep_prds.json file did
    # NOT have a .issues[] toplevel key, and it could be
    # because at the time the job was incomplete. the jq
    # before the slurp below ensures there is an .issues[]
    # key in the event the key is not present in the json
    #
    [[ "${__risk__}" == "authorsRisk" ]] && _say "collecting SDN issues..." && _liseq=0 && \
      for _x in "${SDNhits[@]}";
      do
        ((_liseq++));
        cat <<-_MYSDNEOF
  {
    "tag": "$(jq -r '.confidence' <<<"${_x}"|sed 's/critical/C/g;s/high/H/g')A$(printf %.4d "${_liseq}")",
    "id": "$(jq -r '.repo' <<<"${_x}")",
    "title": "$(jq -r '.lastName' <<<"${_x}") - $(jq -r '.committer' <<<"${_x}") is a contributor found on the Specially Designated Nationals List",
    "description": "### Summary\nPackage repo $(jq -r '.repo' <<<"${_x}") credits one or more contributors found on the SDN list, ($(jq -r '.programList' <<<"${_x}") program list(s)), as an $(jq -r '.sdnType' <<<"${_x}") known as $(jq -r '.lookups|join(" and ")' <<<"${_x}"), with the email $(jq -r '.email_addr' <<<"${_x}").\n\n### Overview\nThis project contains one or more contributions crediited by the maintainers as being provided by an entity or individual that appears on the Specially Designated Nationals and Blocked Persons list ('SDN List') published by US Department of Treasury's Office of Foreign Asset Control (OFAC) used to regulate US sanctions pertaining to those on the SDN List.\n### Impact\nThe US OFAC Sanctions are  'strict liability', which means it does not matter whether you know about them or not. Violating these rules can lead to serious penalties, so it's important to understand how these rules might affect the incorporation of this project's software. The application of U.S. sanctions, including both their prohibitions and exemptions, to open source software or standards-related activities is not 100% well defined, as OFAC has yet to issue clear guidance on whether and how U.S. sanctions apply to open source or standards-related activities.\n\n### References\nhttps://www.linuxfoundation.org/blog/navigating-global-regulations-and-open-source-us-ofac-sanctions.\n\n### Recommendation\nSeek legal counsel regarding potential issues or questions.\n",
    "severity": "$(jq -r '.confidence' <<<"${_x}")",
    "domain": "author",
    "details": null,
    "impact": "$(jq -r '.confidence' <<<"${_x}")",
    "riskType": "authorsRisk"
  }
_MYSDNEOF
      done | jq --slurp 'unique_by(.title,.description,.tag,.id)|sort_by(.tag)' >> "${3}"

    [[ "${__risk__}" == "licenseRisk" ]] && _say "collecting copy-left license issues..." && _liseq=0 && \
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
      done < <(xargs -a "${__ghapiFiles}" -0 jq -r '.git_url,.license.spdx_id' ) \
      | jq --slurp 'unique_by(.title,.description,.tag,.id)|sort_by(.tag)' >> "${3}"
    #
    # TODO: test if __SBOM__ before this find and __PHYLUM__ for the next find
    #
    [[ "${__risk__}" == "vulnerabilities" ]] && 
      [[ ! ${_grype_ver} == "${__NOASSERTION__}" ]] &&
      [[ -s ${__grypeFiles} ]] && _say "collecting grype vulnerabilities..." && \
      xargs -a "${__grypeFiles}" -0 \
        jq --slurp 'unique_by(.title,.description,.tag,.id)|sort_by(.tag)' >> "${3}"

    # jq's arg _risk in quotes is NOT to be a shell expansion
    # false positive https://github.com/koalaman/shellcheck/issues/1160
    #
    # shellcheck disable=2016
    "${_doPhylum}" && _say "collecting Phylum ${__risk__} issues..." && xargs -a "${__phdepFiles}" -0 \
      jq -r --arg _risk "${__risk__}" '
        .
        | if (.issues) then . else . + {"issues": []} end
        | if (.dependencies) then . else . + {"dependencies": [ { "issues":[] } ]} end
        | .issues[]?,.dependencies[].issues[]?
        | select(.riskType==$_risk)
      ' | \
          jq --slurp 'unique_by(.title,.description,.tag,.id)|sort_by(.tag)' >> "${3}"
  done #}

  rm -f "${__ghapiFiles}" "${__phdepFiles}" "${__grypeFiles}"

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
      sed 's/\\/\&#92;/g;s^### Overview^<h4>Overview</h4>^g;s^### Proof of Concept^<h4>Proof of Concept</h4>^g;s^### Importance^<h4>Importance</h4>^g;s^### Description^<h4>Description</h4>^g;s^### Summary^<h4>Summary</h4>^g;s^### Impact^<h4>Impact</h4>^g;s^###  Affected Configuration^<h4>Affected Configuration</h4>^g;s^### Patches^<h4>Patches</h4>^g;s^### Workarounds^<h4>Workarounds</h4>^g;s^### For more information^<h4>For more information</h4>^g;s^### Recommendation^<h4>Recommendation</h4>^g;s^### References^<h4>References</h4>^g;s^\*\*CVE\*\*:^<h4>CVE:</h4>^g;s^\*\*\([[:print:]].*\)\*\*^<b>\1</b>^g;s^:__BR__:^<br/>^g;' >> "${2}_vulmalrep.html"
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
  # since tarball has ':' in the name use 'tar tvfz <boefile>.tgz --force-local'
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

  ! tar hcfz ../"${1}-scir-p4r-boe.tgz" --exclude="*scir-p4r-boe*.tgz*" -C .. "${1}"/ && \
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
      ./*_sbom_grype.json \
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
              "${__ghrcommitjson}" \
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
    # __SBOM__ projects do not have a _job_ file
    #
    [[ ${_fil} =~ _job_ ]] && [[ "${dependency_type}" == "${__SBOM__}" ]] && continue

    [ ! -f "${_fil}" ] &&
      _err "required file, ${_fil}: not found for ${1}" &&
      _rc=1;
  done

  return "${_rc}"
}

do_runtime_localizations()
{
  local _rc=0

  # shellcheck disable=1091
  [[ -f "${_OSSSCIRsettings}/scir-oss/localizations.lib.sh" ]] && source "${_OSSSCIRsettings}/scir-oss/localizations.lib.sh"

  readonly _OSSFSC="${_LOCAL_OSSFSC:-gcr.io/openssf/scorecard:latest}"
  readonly _OSSFCS="${_LOCAL_OSSFCS:-${HOME}/go/bin/criticality_score}"
  readonly _MITRHC="${_LOCAL_MITRHC:-mitre/hipcheck:latest}"
  readonly _GRYPEC="grype"

  _LOCAL_LANG="${_LOCAL_LANG:-en}"
  _LOCAL_CRITERIA_DESC="${_LOCAL_CRITERIA_DESC:-reportWriter_criteria_desc.lib.sh.${_LOCAL_LANG}}"

  ! [[ ${_LOCAL_CRITERIA_DESC:0:1} == '/' ]] && _LOCAL_CRITERIA_DESC="${_OSSSCIRsettings}/scir-oss/${_LOCAL_CRITERIA_DESC}"

  # language localizations are now necessary as _reportWriter uses them
  #
  [[ ! -f "${_LOCAL_CRITERIA_DESC}" ]] && _err "reportWriter localizations '${_LOCAL_CRITERIA_DESC}': not found" &&
    return 1

  ! bash -n "${_LOCAL_CRITERIA_DESC}" 1>/tmp/${$}.out 2>/tmp/${$}.err &&
    _err "reportWriter localizations '${_LOCAL_CRITERIA_DESC}': bash syntax error" &&
      cat /tmp/${$}.err && rm -f "/tmp/${$}.out" "/tmp/${$}.err" &&
      return 1

  rm -f "/tmp/${$}.out" "/tmp/${$}.err"
  # shellcheck disable=1090
  source "${_LOCAL_CRITERIA_DESC}"

  ORGLOOKUP_LABEL="${_LOCAL_ORG_TYPE_LOOKUP_LABEL:-logistics database D-U-N-S code}"

  return 0;
}

#
# will error off if the expected resource and/or values
# need at runtime are not present or unknown for
# binary/commands, docker images, environment vars, and
# command line args
#
check_runtime()
{
  local _info
  _rc=0 # 0 = no error, 1 = non recoverable error

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
      [[ -f "${_OSSSCIRsettings}/scir-oss/_dig4repo-resolv.csv" ]] && _OSSSCIRrepoResolveDB="${_OSSSCIRsettings}/scir-oss/_dig4repo-resolv.csv"
    fi
  }

  # localizations are for organization dependent nomenclature,
  # and local runtime constraints (binaries, containers, etc.)
  ! do_runtime_localizations "${_OSSSCIRsettings}" && _rc=1

  #
  # the required binaries
  #
  # unzip is needed if phylum is to be installed
  for cmd in ps pgrep pkill bc jq curl $(${_useDocker} && echo docker) base64 iconv sha256sum unzip csvtool
  do
    [ -z "$(command -v "${cmd}")" ] &&
      _err "required command, ${cmd}: not found in path or not installed" &&
      _rc=1
  done

  #
  # the optional binaries
  # shellcheck disable=2043
  for cmd in phylum "${_OSSFCS}"
  do
    [ -z "$(command -v "${cmd}")" ] &&
      _warn "optional command, ${cmd}: not found in path or not installed"
  done

  #
  # the docker images if _useDocker is true
  # the command executables if _useDocker is false
  #
  rm -f ./scir-dimg.*
  if ${_useDocker} && ! docker image ls > ./scir-dimg.${$} 2>&1; then
    _err "docker: sudo may be required see '$(realpath ./scir-dimg.${$})' for more details (e.g, sudo -E docker ...)"
    _rc=1
  else
    rm -f "./scir-dimg.${$}"
  fi

  local -n dimg
  for dimg in _OSSFSC _MITRHC
  do
    if "${_useDocker}"; then
      _info "config docker image ${!dimg}=${dimg}"
      local _dimgFile
      _dimgFile=$(docker image ls ${dimg} | grep -E -v "REPOSITORY")
      [ -z "${_dimgFile}" ] &&
        _err "required docker image, ${dimg}: not found" &&
        _rc=1
    else
      _info "config image ${!dimg}=${dimg}"
      [ -z "$(command -v "${cmd}")" ] &&
        _err "required command, ${cmd}: not found in path or not installed" &&
        _rc=1
    fi
  done

  _sdnlist_ver="${__NOASSERTION__}"
  local -n _sp
  for _sp in _OSSSCIRsettings _MITRHCconfig _MITRHCscripts _OSSSCIRlicenseDB _OSSSCIRrepoResolveDB
  do
    _info "config setting ${!_sp}=${_sp}"
    [[ -v ${!_sp} ]] && [[ ! -r "${_sp}" ]] && _err "can't find path/file for ${!_sp}=${_sp}" && _rc=1
  done

  for _sp in _PRIMARY_BLACKLIST _SECONDARY_BLACKLIST _TERTIARY_BLACKLIST
  do
    [[ ${_sp} != "${_NULL_BLACKLIST_}" ]] && _info "env setting ${!_sp}='${_sp}'"
  done

  #
  # made sure these are all readable by container processes, error off if otherwise
  #
  [[ (( $(find "${_MITRHCconfig}" -type d -perm -o=rx|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCconfig}, use chmod go+rx ${_MITRHCconfig}/" && _rc=1
  [[ (( $(find "${_MITRHCconfig}" -type f -perm -o=r|wc -l) -lt 5 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCconfig}, use chmod go+r ${_MITRHCconfig}/*" && _rc=1
  [[ (( $(find "${_MITRHCscripts}" -type d -perm -o=rx|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCscripts}, use chmod go+rx ${_MITRHCscripts}/" && _rc=1
  [[ (( $(find "${_MITRHCscripts}" -type f -perm -o=r|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_MITRHCscripts}, use chmod go+r ${_MITRHCscripts}/*" && _rc=1
  [[ (( $(find "${_OSSSCIRlicenseDB}" -perm -o=r|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_OSSSCIRlicenseDB}, use chmod go+r ${_OSSSCIRlicenseDB}" && _rc=1
  [[ -v _OSSSCIRrepoResolveDB ]] && [[ (( $(find "${_OSSSCIRrepoResolveDB}" -perm -o=r|wc -l) -lt 1 )) ]] && _err "path/files modes not readable by containers for ${_OSSSCIRrepoResolveDB}, use chmod go+r ${_OSSSCIRrepoResolveDB}" && _rc=1
  #
  # grab version numbers for report metadata
  #
  _ossf_scorecard_ver="$($("${_useDocker}" && echo docker run --rm) "${_OSSFSC}" version 2>&1 | grep GitVersion | cut -d: -f2 | sed 's/ //g')"
  [[ -z "${_ossf_scorecard_ver}" ]] && _warn "could not determine OSSF/Scorecard version" && _ossf_scorecard_ver="${__NOASSERTION__}"

  _info="$($("${_useDocker}" && echo docker run --rm) "${_MITRHC}" --version)"
  _mitre_hipcheck_ver="$(grep -o -E '([Hh]ipcheck ([[:alnum:]][. ]*)+)' <<<"${_info}" | sed 's/hipcheck //gi')"
  [[ -z "${_mitre_hipcheck_ver}" ]] && _warn "could not determine MITRE Hipcheck version" && _mitre_hipcheck_ver="${__NOASSERTION__}"
  # assume latest
  # --quiet 3.1.x thru 3.2.1 otherwise '--verbosity quiet' 3.3.0 onward
  # --json 3.1.x thru 3.2.1 otherwise '--format json' 3.3.0 onward
  # check repo 3.1.x thru 3.2.1 otherwise 'check' 3.3.0 onward
  _MITRHCquiet="--verbosity quiet"
  _MITRHCjson="--format json"
  _MITRHCrepoCmd="check"
  _MITRHCnewSchemaVersion="3.12.0"
  case "${_mitre_hipcheck_ver}" in
    3.1.*|3.2.*)
       _MITRHCcache="$($("${_useDocker}" && echo docker run --rm) "${_MITRHC}" --print-home)"
       _MITRHCquiet="${_MITRHCquiet/verbosity /}"
       _MITRHCjson="${_MITRHCjson/format /}"
       _MITRHCrepoCmd="${_MITRHCrepoCmd/check/check repo}"
       ;;
    *)
       _MITRHCcache="$($("${_useDocker}" && echo docker run --rm) "${_MITRHC}" --print-home true)"
       ;;
  esac

  [[ -z "${_MITRHCcache}" ]] && _fatal "could not determine MITRE Hipcheck cache folder" && _MITRHCcache=""

  "${_doPhylum}" && { _phylum_ver="$(phylum --version | cut -d\  -f2)"
  [[ -z "${_phylum_ver}" ]] && _warn "could not determine Phylum CLI version" && _phylum_ver="${__NOASSERTION__}"; }

  _ossf_critscorecard_ver="$(${_OSSFCS} -depsdev-disable https://github.com/ 2>&1 | grep criticality_score@ | cut -d@ -f2|cut -d/ -f1|sort|uniq)"
  [[ -z "${_ossf_critscorecard_ver}" ]] && _warn "could not determine OSSF/criticality_score version" && _ossf_critscorecard_ver="${__NOASSERTION__}"

  # not required (yet)
  # grype appears to auto update when first run specifically for a check
  # so ignore out of date errors at this step
  _grype_ver=""
  [[ -n "$(command -v "${_GRYPEC}")" ]] &&
    _grype_ver="$({ "${_GRYPEC}" --version | cut -d\  -f2; GRYPE_DB_VALIDATE_AGE=false "${_GRYPEC}" db status -o json | jq -r '"db",.schemaVersion,"built on",.built' ; } | tr '\n' ' ')"
  [[ -z "${_grype_ver}" ]] && _warn "could not determine grype version (vul reports skipped)" && _grype_ver="${__NOASSERTION__}"

  #
  #
  #
  [[ -n "${_CAStoreVolume}" ]] \
    && [[ ! -s "${_CAStoreVolume}" ]] \
    && _err "certificate store is empty or does not exist" && _rc=1

  [[ -n "${_CAStoreVolume}" ]] \
    && [[ ! "$(file "${_CAStoreVolume}" | cut -d: -f2)" =~ "PEM certificate" ]] \
    && _err "certificate store is not in PEM format" && _rc=1

  _info "CA Certificate Trust Store ${_CAStoreVolume} (${_CAStoreDocker})"

  #
  # the env
  # TODO: allow a token to be passed on the CMD line (getopt)
  #       or pulled from secrets
  #
  # one var for this loop is okay for now
  # shellcheck disable=2043
  for eVar in GITHUB_AUTH_TOKEN
  do
    ! ${BoEonly} && if [[ -z "${!eVar}" ]]; then
      _err "required env variable, ${eVar}: not set"
      _rc=1
    fi
  done

  [[ "${dependency_type}" == "${__PHYLUM__}" ]] && {
    local _bearer;
    if ! _bearer=$(phylum auth token --bearer 2>/dev/null); then _err "got phylum token? ${?}" && _rc=1; fi
    [ -z "${_bearer}" ] &&
      _err "required phylum bearer token not available, see 'phylum auth status' for details" &&
      _rc=1;
  }

  #
  # the command line
  #
  [ -z "${component}" ] &&
    _err "required local project name not specified (e.g., -C fleetth)" &&
    _rc=1

  [ -z "${dependency_src}" ] &&
    _err "required dependency specification not specified (e.g., -P <phylum project> or -P <[syft|GitHub] sbom file>)" &&
    _rc=1

  [ "${gh_site}" = "${__NULLGH__}" ] &&
    _warn "Github project site not specified for ${component} (e.g., -G ossf/scorecard)"

  if ! [[ "${_cache_days}" =~ ^[0-9]+$ ]]; then
    _err "cache days setting is numeric: ${_cache_days} is non-numeric" &&
    _rc=1
  fi

  _say -n "loading & initializing plugins..."
  _load_scir_plugins "${_OSSSCIRsettings}/scir-oss/plugins"
  _init_scir_plugins
  _say OK

  return ${_rc}
}
_saveOff_json_Computed_scores()
{
  # TODO: determine what to save off
  #
  return 0
}

_saveOff_json_Raw_scores()
{
  local _card
  local _scrs
  local _tt=""

  _card="${1}"

  case "${_card}" in
    MYscore | HCscore)
      _tt="gt";
      ;;
    CIOscore | SCscore)
      _tt="le";
      ;;
    PHYscore)
      ! "${_doPhylum}" && return 0
      _tt="le";
      ;;
    CSscore)
      local _cs
      local _pf
      _cs="$(jq -r '.default_score' "${2}" 2>/dev/null)"
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

#
# inspired by https://github.com/MrMarble/termsvg/blob/master/scripts/update-filesize.sh
#
_compile_other_p4reports()
{
  local _MDTABLE
  local _WWTABLE
  local _col1
  local _col2
  local _col1desc
  local _col2clean
  local id

  #
  # preamble for the MD file
  #
  read -r -d '' _MDTABLE << EOS
  | OSS Project Report | Response |
  |--------------------|:---------|\n
EOS

  #
  # preamble for the www html file
  #
  read -r -d '' _WWTABLE << EOS
  <!DOCTYPE html>
  <html>
  <head>
  <style>
  table, th, td {
  border: 1px solid #cccccc; border-collapse: collapse; padding-left: 10px; padding-right: 10px; padding-top: 7px; padding-bottom: 7px;
}
th {
  background-color: #E7E9EB; text-align: left; }
td {
  word-wrap: break-word; }
  #prDIV {
    font-size: 14px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, "Fira Sans", "Droid Sans", "Helvetica Neue", sans-serif;
-apple-;
  }
  </style>
  </head>
  <body>
  <div id="prDIV">
  <h1>${1} OSS-P4/R</h1>
  <ul>
  <li><a href="#vuls">Critical and High vulnerabilities</a></li>
  <li><a href="#mals">Critical and High maliciousCodeRisk</a></li>
  <li><a href="#engs">Critical and High engineeringRisk</a></li>
  <li><a href="#auts">Critical and High authorsRisk</a></li>
  <li><a href="#lics">Critical, High, Medium, and Low licenseRisk</a></li>
  </ul>
  <p>
  <table>
  <thead><tr><th>OSS Project Report</th><th>Response</th></tr></thead>
  <tbody>
EOS

  while read -r id; do
    IFS="|" read -r _col1 _col2 < <(jq -r --arg ID "${id}" '.reportWriter[]|select (.id == $ID)|[.label,.value]|join("|")' "${2}")
    IFS=    read -r _col1desc   < <(jq -r --arg ID "${id}" '.reportWriter[]|select (.id == $ID)|.description' "${2}")

    #
    # handle special cases (keep this one)
    [[ $id =~ Section___ ]] && _col2="____HRULE____"

    _col2clean=$(sed "s^<ac:emoticon ac:name='warning'/>^(\!)^g;s^<ac:emoticon ac:name='cross'/>^(\x)^g;" <<<"${_col2}")
    _ww__col2clean="${_col2clean}"
    _ww__col2clean=$(sed "s^<ac:emoticon ac:name='warning'/>^${__WARNINGSVG__}^g;s^<ac:emoticon ac:name='cross'/>^${__REDSVGFLAG__}^g;" <<<"${_col2}")

    case "${id}" in
      "${_LOCAL_OSSP4R_OUTLOOK_ID}" | "${_LOCAL_DODCIO_CRITERIA_ID}")
        read -r _col2 < <(jq -r --arg ID "${id}" '.reportWriter[]|select (.id == $ID)|.wwwValue' "${2}")
        _col2clean=$(sed -e 's^background-color:rgba([^;]*;^^g;' <<<"${_col2}")
        _ww__col2clean="${_col2}"
        ;;
      "${_LOCAL_SUMMARIZED_SCORES_BY_CRITERIA_ID}")
        ;;
      *)
        _col2clean=$(sed "s^ ac:name='tr' ^>____BREAK____<^g;s^<br/>^____BREAK____^g;s^<p/>^____BREAK____^g;" <<<"${_col2clean}")
        # shellcheck disable=2001
        _col2clean=$(sed -e 's/<[^>]*>//g;' <<<"${_col2clean}")
        _ww__col2clean=$(sed "s^ ac:name='tr' ^>____BREAK____<^g;s^<br/>^____BREAK____^g;s^<p/>^____BREAK____^g;" <<<"${_ww__col2clean}")
        ;;
    esac

    # careful to escape any embedded '|' which would be
    # interpreted as markdown syntax
    _MDTABLE+="| ${_col1/|/\\|} | ${_col2clean/|/\\|} |\n"
    _WWTABLE+="<tr><td><div title=\"${_col1desc}\"><u>${_col1}</u></div></td><td>${_ww__col2clean}</td></tr>"

  done < <(jq -r '.reportWriter[]|.id' "${2}")

  _WWTABLE+="</tbody></table>"

  #
  # last step - reinflate out allowable html tags and turn the newline token into real newlines
  #
  echo "${_MDTABLE}" | sed 's^\\n^\n^g' | sed 's^____BREAK____^<br>^g;s^____HRULE____^<hr>^g;' > "${1}_scir.md"
  echo "${_WWTABLE}" | sed 's^\\n^\n^g' | sed 's^____BREAK____^<br>^g;s^____HRULE____^<hr style="border: 10px solid gray; border-radius: 5px"/> ^g;s/<td><hr/<td colspan="100"><hr/g' > "${1}_scir.www.html"

  #
  # for the www html version, include all the issues reported
  #
  [[ -f "${1}_vulmalrep.html" ]] && {
    sed 's/<h2>Critical and High vulnerabilities/<h2 id="vuls">Critical and High vulnerabilities/g;
         s/<h2>Critical and High maliciousCodeRisk/<h2 id="mals">Critical and High maliciousCodeRisk/g;
         s/<h2>Critical and High engineeringRisk/<h2 id="engs">Critical and High engineeringRisk/g;
         s/<h2>Critical and High authorsRisk/<h2 id="auts">Critical and High authorsRisk/g;
         s/<h2>Critical, High, Medium, and Low licenseRisk/<h2 id="lics">Critical, High, Medium, and Low licenseRisk/g' \
      "${1}_vulmalrep.html";
  } >> "${1}_scir.www.html"

  #
  # close out the www html file
  #
  echo "</div></body></html>" >> "${1}_scir.www.html"

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
   "id": "${_LOCAL_SECTION___OSS_PROJECT_OVERVIEW_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___OSS_PROJECT_OVERVIEW_LABEL}",
   "description": "${_LOCAL_SECTION___OSS_PROJECT_OVERVIEW_DESC}",
   "risk": "${_LOCAL_SECTION___OSS_PROJECT_OVERVIEW_RISK}"
 },
 {
   "id": "${_LOCAL_BACKGROUND_ID}",
   "value": "$(_background "${__ghrjson}")",
   "label": "${_LOCAL_BACKGROUND_LABEL}",
   "description": "${_LOCAL_BACKGROUND_DESC}",
   "risk": "${_LOCAL_BACKGROUND_RISK}"
 },
 {
   "id": "${_LOCAL_APP_LIBRARY_ID}",
   "value": "Manual (ask)",
   "label": "${_LOCAL_APP_LIBRARY_LABEL}",
   "description": "${_LOCAL_APP_LIBRARY_DESC}",
   "risk": "${_LOCAL_APP_LIBRARY_RISK}"
 },
 {
   "id": "${_LOCAL_CURRENT_AS_OF_ID}",
   "value": "Date: $(date +%m-%d-%Y) (project queried $(_as_of "${__ghrjson}"))",
   "label": "${_LOCAL_CURRENT_AS_OF_LABEL}",
   "description": "${_LOCAL_CURRENT_AS_OF_DESC}",
   "risk": "${_LOCAL_CURRENT_AS_OF_RISK}"
 },
 {
   "id": "${_LOCAL_OSSP4R_OUTLOOK_ID}",
   "value": "$(_p4_outlook "${_SCcard}" "${_HCcard}" "${__component_prds}" | sed 's/"/\\"/g' | tr -d '\n\r')",
   "wwwValue": "$(_p4_outlook --www "${_SCcard}" "${_HCcard}" "${__component_prds}" | sed 's/"/\\"/g' | tr -d '\n\r')",
   "label": "${_LOCAL_OSSP4R_OUTLOOK_LABEL}",
   "description": "${_LOCAL_OSSP4R_OUTLOOK_DESC}",
   "risk": "${_LOCAL_OSSP4R_OUTLOOK_RISK}"
 },
 {
   "id": "${_LOCAL_DODCIO_CRITERIA_ID}",
   "value": "$(_cio_criteria "${_SCcard}" "${_HCcard}" "${__component_prds}" | sed 's/"/\\"/g' | tr -d '\n\r')",
   "wwwValue": "$(_cio_criteria --www "${_SCcard}" "${_HCcard}" "${__component_prds}" | sed 's/"/\\"/g' | tr -d '\n\r')",
   "label": "${_LOCAL_DODCIO_CRITERIA_LABEL}",
   "description": "${_LOCAL_DODCIO_CRITERIA_DESC}",
   "risk": "${_LOCAL_DODCIO_CRITERIA_RISK}"
 },
 {
   "id": "${_LOCAL_SUMMARIZED_SCORES_BY_CRITERIA_ID}",
   "value": "$(_summary_scores_criteria_tbl | sed 's/"/\\"/g' | tr -d '\n\r')",
   "label": "${_LOCAL_SUMMARIZED_SCORES_BY_CRITERIA_LABEL}",
   "description": "${_LOCAL_SUMMARIZED_SCORES_BY_CRITERIA_DESC}",
   "risk": "${_LOCAL_SUMMARIZED_SCORES_BY_CRITERIA_RISK}"
 },
 {
   "id": "${_LOCAL_SECTION___SECURITY_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___SECURITY_LABEL}",
   "description": "${_LOCAL_SECTION___SECURITY_DESC}",
   "risk": "${_LOCAL_SECTION___SECURITY_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___SECURITY_ID}" "${__REPORT__SECTION__HEAD__}")
 {
   "id": "${_LOCAL_TRUSTED_SOURCE_ID}",
   "value": "Source: ${__gh}<br/>${_LOCAL_TRUSTED_SOURCE_NAME_LABEL} Availability: Manual<br/>Repo or Mirror: Manual",
   "label": "${_LOCAL_TRUSTED_SOURCE_LABEL}",
   "description": "${_LOCAL_TRUSTED_SOURCE_DESC}",
   "risk": "${_LOCAL_TRUSTED_SOURCE_RISK}"
 },
 {
   "id": "${_LOCAL_PUBLIC_PRIVATE_ID}",
   "value": "$(_pub_priv "${__ghrjson}")",
   "label": "${_LOCAL_PUBLIC_PRIVATE_LABEL}",
   "description": "${_LOCAL_PUBLIC_PRIVATE_DESC}",
   "risk": "${_LOCAL_PUBLIC_PRIVATE_RISK}"
 },
 {
   "id": "${_LOCAL_FULLY_UNRESTRICTED_ID}",
   "value": "$(_unrestricted "${__ghrjson}")",
   "label": "${_LOCAL_FULLY_UNRESTRICTED_LABEL}",
   "description": "${_LOCAL_FULLY_UNRESTRICTED_DESC}",
   "risk": "${_LOCAL_FULLY_UNRESTRICTED_RISK}"
 },
 {
   "id": "${_LOCAL_LOGIN_CREDENTIALS_ID}",
   "value": "$(_login_cred "${__ghrjson}")",
   "label": "${_LOCAL_LOGIN_CREDENTIALS_LABEL}",
   "description": "${_LOCAL_LOGIN_CREDENTIALS_DESC}",
   "risk": "${_LOCAL_LOGIN_CREDENTIALS_RISK}"
 },
 {
   "id": "${_LOCAL_USE_REPO_PROTECTIONS_ID}",
   "value": "$(_repo_protections "${_SCcard}")",
   "label": "${_LOCAL_USE_REPO_PROTECTIONS_LABEL}",
   "description": "${_LOCAL_USE_REPO_PROTECTIONS_DESC}",
   "risk": "${_LOCAL_USE_REPO_PROTECTIONS_RISK}"
 },
 {
   "id": "${_LOCAL_HAS_LARGE_COMMITS_ID}",
   "value": "$(_large_commits "${_SCcard}" "${_HCcard}") (Churn)",
   "label": "${_LOCAL_HAS_LARGE_COMMITS_LABEL}",
   "description": "${_LOCAL_HAS_LARGE_COMMITS_DESC}",
   "risk": "${_LOCAL_HAS_LARGE_COMMITS_RISK}"
 },
 {
   "id": "${_LOCAL_OBFUSCATED_CODE_ID}",
   "value": "$(_obscure_code "${_SCcard}" "${_HCcard}") (Entropy)",
   "label": "${_LOCAL_OBFUSCATED_CODE_LABEL}",
   "description": "${_LOCAL_OBFUSCATED_CODE_DESC}",
   "risk": "${_LOCAL_OBFUSCATED_CODE_RISK}"
 },
 {
   "id": "${_LOCAL_HAVE_BINARY_ARTIFACTS_ID}",
   "value": "$(_binary_artifacts "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_HAVE_BINARY_ARTIFACTS_LABEL}",
   "description": "${_LOCAL_HAVE_BINARY_ARTIFACTS_DESC}",
   "risk": "${_LOCAL_HAVE_BINARY_ARTIFACTS_RISK}"
 },
 {
   "id": "${_LOCAL_TYPOSQUATTING_RISK_ID}",
   "value": "$(_typo_risk "${component}_allIssues.json" "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_TYPOSQUATTING_RISK_LABEL}",
   "description": "${_LOCAL_TYPOSQUATTING_RISK_DESC}",
   "risk": "${_LOCAL_TYPOSQUATTING_RISK_RISK}"
 },
 $( "${_doPhylum}" && cat <<-_phylumeof
 {
   "id": "${_LOCAL_ENG_RISK_ID}",
   "value": "$(_eng_risk "${component}_allIssues.json")",
   "label": "${_LOCAL_ENG_RISK_LABEL}",
   "description": "${_LOCAL_ENG_RISK_DESC}",
   "risk": "${_LOCAL_ENG_RISK_RISK}"
 },
 {
   "id": "${_LOCAL_MALICIOUS_CODE_ID}",
   "value": "$(_mal_code "${component}_allIssues.json")",
   "label": "${_LOCAL_MALICIOUS_CODE_LABEL}",
   "description": "${_LOCAL_MALICIOUS_CODE_DESC}",
   "risk": "${_LOCAL_MALICIOUS_CODE_RISK}"
 },
_phylumeof
 )
 {
   "id": "${_LOCAL_VULN_CHECK_ID}",
   "value": "$(_vul_check "${component}_allIssues.json" "${_SCcard}")",
   "label": "${_LOCAL_VULN_CHECK_LABEL}",
   "description": "${_LOCAL_VULN_CHECK_DESC}",
   "risk": "${_LOCAL_VULN_CHECK_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___SECURITY_ID}" "${__REPORT__SECTION__TAIL__}")
 {
   "id": "${_LOCAL_SECTION___INTEGRITY_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___INTEGRITY_LABEL}",
   "description": "${_LOCAL_SECTION___INTEGRITY_DESC}",
   "risk": "${_LOCAL_SECTION___INTEGRITY_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___INTEGRITY_ID}" "${__REPORT__SECTION__HEAD__}")
 {
   "id": "${_LOCAL_CONDUCT_PEER_REVIEWS_ID}",
   "value": "$(_peer_reviews "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_CONDUCT_PEER_REVIEWS_LABEL}",
   "description": "${_LOCAL_CONDUCT_PEER_REVIEWS_DESC}",
   "risk": "${_LOCAL_CONDUCT_PEER_REVIEWS_RISK}"
 },
 {
   "id": "${_LOCAL_USE_CODE_SECURITY_SCANNERS_ID}",
   "value": "$(_code_scanners "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_USE_CODE_SECURITY_SCANNERS_LABEL}",
   "description": "${_LOCAL_USE_CODE_SECURITY_SCANNERS_DESC}",
   "risk": "${_LOCAL_USE_CODE_SECURITY_SCANNERS_RISK}"
 },
 {
   "id": "${_LOCAL_SIGNED_COMMITS_ID}",
   "value": "$(_dcoSigned_commits /dev/null)",
   "label": "${_LOCAL_SIGNED_COMMITS_LABEL}",
   "description": "${_LOCAL_SIGNED_COMMITS_DESC}",
   "risk": "${_LOCAL_SIGNED_COMMITS_RISK}"
 },
 {
   "id": "${_LOCAL_CRYPTO_SIGNED_COMMITS_ID}",
   "value": "$(_signed_commits "${__ghrcommitjson}")",
   "label": "${_LOCAL_CRYPTO_SIGNED_COMMITS_LABEL}",
   "description": "${_LOCAL_CRYPTO_SIGNED_COMMITS_DESC}",
   "risk": "${_LOCAL_CRYPTO_SIGNED_COMMITS_RISK}"
 },
 {
   "id": "${_LOCAL_CRYPTO_SIGNED_RELEASES_ARTIFACTS_ID}",
   "value": "$(_signed_releases "${_SCcard}")",
   "label": "${_LOCAL_CRYPTO_SIGNED_RELEASES_ARTIFACTS_LABEL}",
   "description": "${_LOCAL_CRYPTO_SIGNED_RELEASES_ARTIFACTS_DESC}",
   "risk": "${_LOCAL_CRYPTO_SIGNED_RELEASES_ARTIFACTS_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___INTEGRITY_ID}" "${__REPORT__SECTION__TAIL__}")
 {
   "id": "${_LOCAL_SECTION___DEPENDENCIES_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___DEPENDENCIES_LABEL}",
   "description": "${_LOCAL_SECTION___DEPENDENCIES_DESC}",
   "risk": "${_LOCAL_SECTION___DEPENDENCIES_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___DEPENDENCIES_ID}" "${__REPORT__SECTION__HEAD__}")
 {
   "id": "${_LOCAL_SBOM_ID}",
   "value": "$(_sbom_val "$({ [[ "${dependency_type}" == "${__PHYLUM__}" ]] && echo "${__ghrsbomjson}"; } || echo "${dependency_src}")")<br/>Language package managers detected: $(_sbom_pkgs "${__component_prjs}")",
   "label": "${_LOCAL_SBOM_LABEL}",
   "description": "${_LOCAL_SBOM_DESC}",
   "risk": "${_LOCAL_SBOM_RISK}"
 },
 {
   "id": "${_LOCAL_DEPENDENCIES_PINNED_ID}",
   "value": "$(_dep_pinned "${_SCcard}")",
   "label": "${_LOCAL_DEPENDENCIES_PINNED_LABEL}",
   "description": "${_LOCAL_DEPENDENCIES_PINNED_DESC}",
   "risk": "${_LOCAL_DEPENDENCIES_PINNED_RISK}"
 },
 {
   "id": "${_LOCAL_DEPENDENCIES_UP_TO_DATE_ID}",
   "value": "$(_dep_up2date "${_SCcard}")",
   "label": "${_LOCAL_DEPENDENCIES_UP_TO_DATE_LABEL}",
   "description": "${_LOCAL_DEPENDENCIES_UP_TO_DATE_DESC}",
   "risk": "${_LOCAL_DEPENDENCIES_UP_TO_DATE_RISK}"
 },
 {
   "id": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_OSS_ID}",
   "value": "Primary: $(_project_dep "${component}" "${__component_prjs}" | tr -d '\n\r')<br/>Secondary: $(_project_dep --sec "${component}" "${__component_prjs}" | tr -d '\n\r')<br/>Tertiary and greater (Max search depth realized $(_max_project_dep "${__component_prjs}")): $(_project_dep --ter "${component}" "${__component_prjs}" | tr -d '\n\r')",
   "label": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_OSS_LABEL}",
   "description": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_OSS_DESC}",
   "risk": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_OSS_RISK}"
 },
 {
   "id": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_PROPRIETARY_ID}",
   "value": "Primary: Manual<br/>Secondary and tertiary: Manual",
   "label": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_PROPRIETARY_LABEL}",
   "description": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_PROPRIETARY_DESC}",
   "risk": "${_LOCAL_DEPENDENCIES_NUMBER_PRIMARY_OTHER_PROPRIETARY_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___DEPENDENCIES_ID}" "${__REPORT__SECTION__TAIL__}")
 {
   "id": "${_LOCAL_SECTION___MALICIOUS_ACTORS_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___MALICIOUS_ACTORS_LABEL}",
   "description": "${_LOCAL_SECTION___MALICIOUS_ACTORS_DESC}",
   "risk": "${_LOCAL_SECTION___MALICIOUS_ACTORS_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___MALICIOUS_ACTORS_ID}" "${__REPORT__SECTION__HEAD__}")
 {
   "id": "${_LOCAL_BAD_AUTHOR_VULS_ID}",
   "value": "Manual",
   "label": "${_LOCAL_BAD_AUTHOR_VULS_LABEL}",
   "description": "${_LOCAL_BAD_AUTHOR_VULS_DESC}",
   "risk": "${_LOCAL_BAD_AUTHOR_VULS_RISK}"
 },
 {
   "id": "${_LOCAL_BAD_AUTHOR_MALICIOUS_ID}",
   "value": "$(_badactors "${__component_prds}" "${_HCcard}")",
   "label": "${_LOCAL_BAD_AUTHOR_MALICIOUS_LABEL}",
   "description": "${_LOCAL_BAD_AUTHOR_MALICIOUS_DESC}",
   "risk": "${_LOCAL_BAD_AUTHOR_MALICIOUS_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___MALICIOUS_ACTORS_ID}" "${__REPORT__SECTION__TAIL__}")
 {
   "id": "${_LOCAL_SECTION___LONG_TERM_SUPPORT_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___LONG_TERM_SUPPORT_LABEL}",
   "description": "${_LOCAL_SECTION___LONG_TERM_SUPPORT_DESC}",
   "risk": "${_LOCAL_SECTION___LONG_TERM_SUPPORT_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___LONG_TERM_SUPPORT_ID}" "${__REPORT__SECTION__HEAD__}")
 {
   "id": "${_LOCAL_PROJECT_BACKGROUND_REPRISE_ID}",
   "value": "$(_background "${__ghrjson}")",
   "label": "${_LOCAL_PROJECT_BACKGROUND_REPRISE_LABEL}",
   "description": "${_LOCAL_PROJECT_BACKGROUND_REPRISE_DESC}",
   "risk": "${_LOCAL_PROJECT_BACKGROUND_REPRISE_RISK}"
 },
 {
   "id": "${_LOCAL_USER_ORG_ID}",
   "value": "$(_user_org "${__ghrjson}")",
   "label": "${_LOCAL_USER_ORG_LABEL}",
   "description": "${_LOCAL_USER_ORG_DESC}",
   "risk": "${_LOCAL_USER_ORG_RISK}"
 },
 {
   "id": "${_LOCAL_ORG_TYPE_ID}",
   "value": "$(_org_type "${__ghrjson}")",
   "label": "${_LOCAL_ORG_TYPE_LABEL}",
   "description": "${_LOCAL_ORG_TYPE_DESC}",
   "risk": "${_LOCAL_ORG_TYPE_RISK}"
 },
 {
   "id": "${_LOCAL_SLSA_LEVEL_ID}",
   "value": "$(_slsa_level "${__ghhtml}")",
   "label": "${_LOCAL_SLSA_LEVEL_LABEL}",
   "description": "${_LOCAL_SLSA_LEVEL_DESC}",
   "risk": "${_LOCAL_SLSA_LEVEL_RISK}"
 },
 {
   "id": "${_LOCAL_BEST_PRACTICES_ID}",
   "value": "$(_best_practices "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_BEST_PRACTICES_LABEL}",
   "description": "${_LOCAL_BEST_PRACTICES_DESC}",
   "risk": "${_LOCAL_BEST_PRACTICES_RISK}"
 },
 {
   "id": "${_LOCAL_OSSF_CRIT_SCORE_ID}",
   "value": "$(_criticality_score "${_CScard}") (higher's better)",
   "label": "${_LOCAL_OSSF_CRIT_SCORE_LABEL}",
   "description": "${_LOCAL_OSSF_CRIT_SCORE_DESC}",
   "risk": "${_LOCAL_OSSF_CRIT_SCORE_RISK}"
 },
 {
   "id": "${_LOCAL_DAYS_LAST_COMMIT_ID}",
   "value": "Days since last commit: $(_day_last "${__ghrjson}")<br/>Days since first commit: $(_day_first "${__ghrjson}")<br/>Activity: $(_maintained "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_DAYS_LAST_COMMIT_LABEL}",
   "description": "${_LOCAL_DAYS_LAST_COMMIT_DESC}",
   "risk": "${_LOCAL_DAYS_LAST_COMMIT_RISK}"
 },
 {
   "id": "${_LOCAL_CORE_CONTRIB_MAINTAINER_COUNT_ID}",
   "value": "Core: $(_maintainers "${_SCcard}" "${_HCcard}")<br/>Other: $(_contrib_count "${__ghrcontribjson}")<br/>Organizational diversity: $(_contrib_org "${_SCcard}" "${_HCcard}")",
   "label": "${_LOCAL_CORE_CONTRIB_MAINTAINER_COUNT_LABEL}",
   "description": "${_LOCAL_CORE_CONTRIB_MAINTAINER_COUNT_DESC}",
   "risk": "${_LOCAL_CORE_CONTRIB_MAINTAINER_COUNT_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___LONG_TERM_SUPPORT_ID}" "${__REPORT__SECTION__HERE__}")
{
   "id": "${_LOCAL_VUL_REPORTING_PROCESS_ID}",
   "value": "$(_vulsec_reporting "${_SCcard}")",
   "label": "${_LOCAL_VUL_REPORTING_PROCESS_LABEL}",
   "description": "${_LOCAL_VUL_REPORTING_PROCESS_DESC}",
   "risk": "${_LOCAL_VUL_REPORTING_PROCESS_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___LONG_TERM_SUPPORT_ID}" "${__REPORT__SECTION__TAIL__}")
 {
   "id": "${_LOCAL_SECTION___SUITABILITY_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___SUITABILITY_LABEL}",
   "description": "${_LOCAL_SECTION___SUITABILITY_DESC}",
   "risk": "${_LOCAL_SECTION___SUITABILITY_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___SUITABILITY_ID}" "${__REPORT__SECTION__HEAD__}")
 {
   "id": "${_LOCAL_LICENSE_NAME_ID}",
   "value": "$(_license_name "${__ghrjson}" | sed 's^ SPDX_ID^<br/>SPDX_ID^g')",
   "label": "${_LOCAL_LICENSE_NAME_LABEL}",
   "description": "${_LOCAL_LICENSE_NAME_DESC}",
   "risk": "${_LOCAL_LICENSE_NAME_RISK}"
 },
 {
   "id": "${_LOCAL_LICENSE_RISK_ID}",
   "value": "$(_license_risk "${component}_allIssues.json")",
   "label": "${_LOCAL_LICENSE_RISK_LABEL}",
   "description": "${_LOCAL_LICENSE_RISK_DESC}",
   "risk": "${_LOCAL_LICENSE_RISK_RISK}"
 },
 {
   "id": "${_LOCAL_SANCTIONED_AUTHOR_ID}",
   "value": "$(_sdnactors "${__ghrcommitjson}")",
   "label": "${_LOCAL_SANCTIONED_AUTHOR_LABEL}",
   "description": "${_LOCAL_SANCTIONED_AUTHOR_DESC}",
   "risk": "${_LOCAL_SANCTIONED_AUTHOR_RISK}"
 },
$(_report_scir_plugins "${_LOCAL_SECTION___SUITABILITY_ID}" "${__REPORT__SECTION__TAIL__}")
 {
   "id": "${_LOCAL_SECTION___REPORT_METADATA_ID}",
   "value": "${__SECTION__}",
   "label": "${_LOCAL_SECTION___REPORT_METADATA_LABEL}",
   "description": "${_LOCAL_SECTION___REPORT_METADATA_DESC}",
   "risk": "${_LOCAL_SECTION___REPORT_METADATA_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_CREATE_ID}",
   "value": "$(date)",
   "label": "${_LOCAL_METADATA_CREATE_LABEL}",
   "description": "${_LOCAL_METADATA_CREATE_DESC}",
   "risk": "${_LOCAL_METADATA_CREATE_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_VERSION_ID}",
   "value": "${_version}",
   "label": "${_LOCAL_METADATA_VERSION_LABEL}",
   "description": "${_LOCAL_METADATA_VERSION_DESC}",
   "risk": "${_LOCAL_METADATA_VERSION_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_PHYPRJID_ID}",
   "value": "$(_phylum_prjId "${dependency_src}" "${__phy_prjs}")",
   "label": "${_LOCAL_METADATA_PHYPRJID_LABEL}",
   "description": "${_LOCAL_METADATA_PHYPRJID_DESC}",
   "risk": "${_LOCAL_METADATA_PHYPRJID_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_PHYJOBID_ID}",
   "value": "$(_phylum_jobReport --readOnly "${dependency_src}" "${__component_prds}")",
   "label": "${_LOCAL_METADATA_PHYJOBID_LABEL}",
   "description": "${_LOCAL_METADATA_PHYJOBID_DESC}",
   "risk": "${_LOCAL_METADATA_PHYJOBID_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_RUNTIME_ID}",
   "value": "Approximately $(_thisRuntime "${__RUNTIME__}") minute(s) (this run), for a total of $(_totalRuntime 'run-*log')",
   "label": "${_LOCAL_METADATA_RUNTIME_LABEL}",
   "description": "${_LOCAL_METADATA_RUNTIME_DESC}",
   "risk": "${_LOCAL_METADATA_RUNTIME_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_CMDLINE_ID}",
   "value": "${_cmdline}",
   "label": "${_LOCAL_METADATA_CMDLINE_LABEL}",
   "description": "${_LOCAL_METADATA_CMDLINE_DESC}",
   "risk": "${_LOCAL_METADATA_CMDLINE_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_DEPTHS_ID}",
   "value": "$(_max_project_dep "${__component_prjs}"), ${scoreDepth}",
   "label": "${_LOCAL_METADATA_DEPTHS_LABEL}",
   "description": "${_LOCAL_METADATA_DEPTHS_DESC}",
   "risk": "${_LOCAL_METADATA_DEPTHS_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_COMMENT_ID}",
   "value": "${_HTMLcaveats[@]}",
   "label": "${_LOCAL_METADATA_COMMENT_LABEL}",
   "description": "${_LOCAL_METADATA_COMMENT_DESC}",
   "risk": "${_LOCAL_METADATA_COMMENT_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_CREDITS_ID}",
   "value": "<a href='https://github.com/ossf/scorecard'>OSSF/Scorecard ${_ossf_scorecard_ver}</a>, <a href='https://github.com/ossf/criticality_score'>OSSF/Critical Score ${_ossf_critscorecard_ver}</a>, <a href='https://github.com/mitre/hipcheck'>MITRE Hipcheck ${_mitre_hipcheck_ver}</a>, $( "${_doPhylum}" && echo "<a href='https://phylum.io'>Phylum.io ${_phylum_ver}</a>, ")<a href='https://github.com/anchore/grype'>grype ${_grype_ver}</a>, <a href='https://sanctionslist.ofac.treas.gov/Home/SdnList'>OFAC SDN last updated ${_sdnlist_ver}</a>",
   "label": "${_LOCAL_METADATA_CREDITS_LABEL}",
   "description": "${_LOCAL_METADATA_CREDITS_DESC}",
   "risk": "${_LOCAL_METADATA_CREDITS_RISK}"
 },
 {
   "id": "${_LOCAL_METADATA_FOOTNOTES_ID}",
   "value": "${_HTMLfootnotes[@]}",
   "label": "${_LOCAL_METADATA_FOOTNOTES_LABEL}",
   "description": "${_LOCAL_METADATA_FOOTNOTES_DESC}",
   "risk": "${_LOCAL_METADATA_FOOTNOTES_RISK}"
 }
 ],
 "rawScores": [
   {
     "mycheck": [ $(_saveOff_json_Raw_scores "MYscore") ],
     "criticalityScore": [ $(_saveOff_json_Raw_scores "CSscore" "${_CScard}") ],
     "scorecard": [ $(_saveOff_json_Raw_scores "SCscore") ],
     "hipcheck": [ $(_saveOff_json_Raw_scores "HCscore") ],
     "phylum": [ $(_saveOff_json_Raw_scores "PHYscore") ]
   }
 ],
 "computedScores": [
   {
     "ossp4r": [ $(_saveOff_json_Computed_scores "MYscore") ],
     "stakeHolder": [ $(_saveOff_json_Computed_scores "MYscore") ]
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
    # ! pushd "${component}" >&"${_fdwarn}" && _fatal "working directory for ${component} not found"
    _say "Only producing the BoE for ${component}";
    if ! produce_BoE "${component}"; then
      _fatal "BoE production failed for ${component}"
    fi;
    return
  }

  build_caches

  #
  # TODO: perform an equiv check if an SBOM is materially newer
  #       than an existing SBOM (e.g., using jqdiff.sh tool)
  #
  ! ${protectNoUpdate} && [ -s "${__component_prds}" ] && {
    __jobStatus="$(_phylum_jobStatus "${dependency_src}" "${__component_prds}")";
    _phylum_jobId_BHDT="true"
    [[ "${__jobStatus}" == "incomplete" ]] && { \
      _say "Existing phylum analysis job was ${__jobStatus}, rebuilding ${__component_prds}";
      component_dep_rebuild="true";
    }
    _job="$(_phylum_jobId "${dependency_src}" "${__component_prds}")"
    [[ -n "${_job}" ]] && [[ "${__jobStatus}" == "complete" ]] && \
      [[ "${dependency_src}_job_${_job/,*/}.json" -nt "${__component_prds}" ]] && {
        _say "Existing phylum analysis job is ${__jobStatus} but newer, rebuilding ${__component_prds}";
        component_dep_rebuild="true";
    }
  }

  _say "checking dependencies..."
  _level=1
  ${BFLAGS[deps]} && component_dep_rebuild="true"
  { ${force_rebuild} || ${component_dep_rebuild} ||
    [ ! -s "${__component_prds}" ] || [ ! -s "${__component_prjs}" ]; } &&
      _say "rebuilding links to ${component} dependencies..." &&
      _phylum_dep_components "${component}" "${__phy_prjs}" \
        "${__component_prds}" "${__component_prjs}" "${_level}" &&
      scorecard_rebuild="true" &&
      component_subdep_rebuild="true" && _line="0,${__gh},${__gh},${__gh},000" &&
      ! grep -q -o -E "(^${_line}$)" "${__component_prjs}" &&
          echo "${_line}" >> "${__component_prjs}";

  #
  # TODO: go n levels deep on dependencies
  #       based on dependency specifications
  #       still under test not happy with output yet
  # TODO: trigger a subdep rebuild of depth changed
  #       to be automatic workaround is the -f subdeps flag
  #
  #        [ ! -s "${__component_prjs}".subs ]) &&
_say "checking sub-dependencies..."
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
  { ! grep -q --fixed-strings 'digraph G {' "${__component_dep_graph}" 2>/dev/null && \
    ! grep -q --fixed-strings '^}' "${__component_dep_graph}" 2>/dev/null; } \
      && _warn "${__component_dep_graph}: missing or incomplete."
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
  _say "checking score cards..."
  { ${BFLAGS[cards]} || ${scorecard_rebuild} || ${force_rebuild} ||
    [ ! -d deps.d/ ]; } &&
      _say "rebuilding scorecards for ${component} dependencies..." &&
      build_scorecards "${__ghrjson}" "${__component_prjs}" "${scoreDepth}"

  #
  # TODO: would like to do this in _run_mychecks()
  _say "checking OFAC SDNs" && detect_sdn "${__sdnDB}"
  #
  # TODO: only validate if building scorecards
  #       above resulted in a change
  #
  # shellcheck disable=2143
  _say "checking for new scores..."
  [ -f "${component}_coalesce.csv" ] &&
    find . -newer "${component}_coalesce.csv" -type f \
      \( -path "*/deps.d/*[sh]c.json*" -o \
         -path "*/subdeps.d/*[sh]c.json*" -o \
         -path \*hc.txt \) \
         -print | \
      grep -q -v -E '(skip)' && \
    _say "Detected updated/new scores" && newScores=true

  { ${BFLAGS[scores]} || ${newScores} || ${force_rebuild} ||
    [ ! -d deps.d/ ] || [ ! -s "${component}_coalesce.csv" ]; } &&
      _say "validating scorecards for ${component} dependencies..." &&
      validate_scorecards "${__component_prjs}" "${scoreDepth}"

  #
  # TODO: add Project, Policy, and Protection
  #       OSS-P4/R scores from SC scorecard (only)
  #       to the coalesced scores file
  #
  coalesce_header="true"
  { ${newScores} || ${force_rebuild} ||
    [ ! -s "${component}_coalesce.csv" ]; } &&
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
  _say "checking for new issues..."
  { ${BFLAGS[issues]} || ${force_rebuild} ||
    [ ! -s "${component}_allIssues.json" ]; }  &&
      _say "consolidating issues for ${component}..." &&
      consolidate_issues "all" "${component}" "${component}_allIssues.json" "${__component_prjs}"

  { [[ "${component}_allIssues.json" -nt "${component}_vulmalrep.html" ]] || "${do_reports}" ||
    [ ! -s "${component}_vulmalrep.html" ]; } &&
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
      map("<tr><td><div title=\\\"" + .description + "\\\"><u>" + .label + "</u></div></td><td>" + (.value | tostring) + "</td></tr>") |
      ["<table><tr><th>OSS Project Report</th><th>Response</th></tr>"] + . + ["</table>"] |
      .[]
      ' "${component}_scir.json" > "${component}_scir.html" && _rc="OK"
    _say "${_rc}"
    _rc="Failed"
    _say -n "Generating ${component}_scir.md and ${component}_scir.www.html..." && _compile_other_p4reports "${component}" "${component}_scir.json" && _rc="OK"
    _say "${_rc}"
  }

  ${build_BoE} && {
    _say -n "Producing the BoE for ${component}...";
    if ! produce_BoE "${component}"; then
      _fatal "BoE production failed for ${component}"
    fi;
  }

  return 0
}

readonly _bldFlags="'all', or one or more of: cards,caches,deps,subdeps,meta,crit,scard,hcheck,scores,issues,job"
readonly _indFlags="caches cards crit deps hcheck issues job meta scard scores subdeps"
_updatingFlag="false"

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
  [caches]="cached data from github (home page, contributors, SBOM), and other project data" \
  [cards]="forces all scorecards and checks to run and retry previous error, no cached data is changed" \
  [crit]="forces OSSF Criticality Score to refresh" \
  [deps]="rebuilds all primary dependencies" \
  [hcheck]="forces MITRE Hipcheck to refresh" \
  [issues]="rebuilds issues from all dependencies" \
  [job]="rechecks project dependency source for updates" \
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

#
# plugin interface
#
declare -A scir_plugins

#
# hints to control where plugin reports
# should be emitted in report output
#
# near the beginning of a section
readonly __REPORT__SECTION__HEAD__="__RHEAD__"
# anywhere in a section
readonly __REPORT__SECTION__HERE__="__RHERE__"
# near the end of a section
readonly __REPORT__SECTION__TAIL__="__RTAIL__"

#
# arguments
# 1: FQ Path for the plugins folder from which to source plugins
#
_load_scir_plugins()
{
  local _fn
  local _bn
  local _pn

  while IFS= read -r _fn
  do
    [[ -f "${_fn}" ]] || \
      { _warn "can't read ${_fn}, skipping..."; continue; }

    _bn="$(basename "${_fn}")"
    grep -q "^[[:space:]]*${_bn/_plugin.sh/}_enabled=true[[:space:]]*$" "${_fn}" || \
      { _warn "plugin disabled ${_fn}, skipping..."; continue; }

    # shellcheck disable=1090
    source "${_fn}" || { _warn "can't source ${_fn}, skipping..."; continue; };

    scir_plugins["${_bn/_plugin.sh/}"]=${_bn/_plugin.sh/}
    _pn=${_bn/_plugin.sh/}_name

    _say -n "${scir_plugins["${_bn/_plugin.sh/}"]}: (${!_pn}), "

  done < <(find "${1}" -maxdepth 1 -type f -name \*_plugin.sh)

  return 0
}

_init_scir_plugins()
{
  local _fn

  while IFS= read -r _x
  do
    _fn=${_x}_init
    [[ -n "$(command -v "${!_fn}")" ]] && ${!_fn}
  done < <(tr ' ' '\n' <<<"${scir_plugins[@]}")

  return 0
}

_cache_scir_plugins()
{
  local _fn

  while IFS= read -r _x
  do
    _fn=${_x}_cache
    [[ -n "$(command -v "${!_fn}")" ]] && ${!_fn}
  done < <(tr ' ' '\n' <<<"${scir_plugins[@]}")

  return 0
}

#
# args are:
#  1: "${component}" passed by -C as in 'oparest'
#     this is the prefix for files generally created by OSS-P4/R
#  2: "$(basename "${gh_site}")" basename as in 'opa-restful' as passed by -G as in 'go-training/opa-restful'
#     this is the prefix for cache files from github API and git CLI
#  3: (future reserved)
#  4: (future reserved)
#
_run_scir_plugins()
{
  local _fn

  while IFS= read -r _x
  do
    _fn=${_x}_run
    [[ -n "$(command -v "${!_fn}")" ]] && {
      ${!_fn} "${1}" "${2}" "${3}" "${4}";
      _fn=${_fn/_run/_detailreport}
      [[ -f "${!_fn}" ]] && _info "${_x}: generated a detail report in ${!_fn}"
    }
  done < <(tr ' ' '\n' <<<"${scir_plugins[@]}")

  return 0
}

_report_scir_plugins()
{
  local _fn
  local _sc
  local _lo
  local _id
  local _label
  local _desc
  local _risk
  local _section
  local _position
  local default_position

  # shellcheck disable=2034
  default_position="${__REPORT__SECTION__TAIL__}"
  _section="${1}"
  _position="${2}"
  while IFS= read -r _x
  do
    _fn=${_x}_report
    _sc=${_x}_section
    _lo=${_x}_position

    [[ -z "${!_lo}" ]] && _lo=default_position

    [[ -n "$(command -v "${!_fn}")" ]] && \
      [[  ${!_sc} = "${_section}" ]] && [[  ${!_lo} = "${_position}" ]] && {
     _id=${_x}_id
     _label=${_x}_label
     _desc=${_x}_desc
     _risk=${_x}_risk
     echo "{"
     echo "\"id\": \"${!_id}\",";
     echo "\"value\": \"$(${!_fn})\",";
     echo "\"label\": \"${!_label}\","
     echo "\"description\": \"${!_desc}\","
     echo "\"risk\": \"${!_risk}\""
     echo "},"
    }
  done < <(tr ' ' '\n' <<<"${scir_plugins[@]}")

  return 0
}

###############################
###############################
# __entrypoint__ ()
###############################
###############################
#{

#
# this is (now) the main entrypoint script for all oss-p4/r
# capabilities, that being analysis (scir-oss.sh)
# and publishing (pub-scir.sh).
#
case "${1,,}" in
  publish)
   shift 1
   exec "$(dirname "$(realpath "$(command -v "${0}")")")/pub-scir.sh" "${@}"
   ;;
  analyze | report)
   shift 1
   ;;
  -h|--h|--help|*) cat <<-_ENPTEOF
  USAGE: ${0} COMMAND [OPTIONS]

  COMMAND

  analyze  Analyze to create or update and OSS-P4/R
  publish  Publish a previously created OSS-P4/R analysis to Altassan's Confluence

  For more information, run ${0} COMMAND -h
_ENPTEOF
  exit 0
   ;;
esac

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

_doPhylum="false"
do_reports="false"
quiet="false"
verbose="false"
dependencyDepth="3"
scoreDepth=0
issueDepth="auto"
scoreTimeout=""

component=
puri="${__NULLPURI__}"
report_type=all
gh_site="${__NULLGH__}"
dependency_src=${component}
dependency_type=

#
# variations and constrains when running IN a container
#
_useDocker=true
_wkgDir="."
[[ -n ${SCIR_CONTAINER} ]] && "${SCIR_CONTAINER}" && {
  _useDocker=false
  _wkgDir="oss-p4r"
}

#
# errors always go to stderr
#
exec 7>&2
_fderr=7
_fdwarn=7

#
# never send to stdout
#
_fdverbose=/dev/null
__logger="cat"
__logfil="${__NULLLOG__}"

_cmdline="${0} analyze ${*}"

#
# check bash version for compatibility issues
#
# bash 5.2 changed behavior of test -v on associative arrays indexed by @
# using compat51 is a workaround for this test given how much it is used
# in this scripts
# TODO: work an acceptable bash 5.0 and greater test for unset associative
#       arrays and remove this shopt
#
# this is an acceptable test for version numbers according to shellcheck
# shellcheck disable=2072
[[ (( "${BASH_VERSION/[^0-9.]*/}" > 5.1 )) ]] && { 
  # shellcheck disable=2034
  BASH_COMPAT=51
}

while getopts "c:d:f:hi:lopquvBC:D:G:L:OP:U:VW:Z:" opt; do #{
  case $opt in
    c) _cache_days="${OPTARG}" ;;
    d) dependencyDepth="${OPTARG}"
       ! [[ ${dependencyDepth} =~ ^[0-9]+$ ]] && \
         [[ ${dependencyDepth} != "all" ]] && \
         _fatal "expecting a positive integer for dependencyDepth (${dependencyDepth})"
       ;;
    f) ! _set_bldFlags "${OPTARG}" && _fatal "build_flags: expecting ${_bldFlags}"
       ;;
    i) issueDepth="${OPTARG}"
       ! [[ ${issueDepth} =~ ^[0-9]+$ ]] && \
         [[ ${issueDepth} != "all" ]] && [[ ${issueDepth} != "auto" ]] && \
         _fatal "expecting a positive integer for issue depth (${issueDepth})"
       ;;
    l) __logfil="run-$(date +%Y%m%d-%H%M%S).log" ;;
    o) BoEonly="true"; build_BoE="true" ;;
    p) protectNoUpdate="true" ;;
    q) quiet="true" ;;
    u) _updatingFlag="true"
       _warn "Updating flag (-u) is experimental at this point as old items are not purged"
       ;;
    v) verbose="true" ;;
    B) build_BoE="true" ;;
    C) component="${OPTARG}" ;;
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
    P) dependency_src="${OPTARG}"
       case "${dependency_src/*:/}" in
         sbom)
           dependency_src="${dependency_src/:sbom/}"
           [ -s "${dependency_src}" ] && [ -f "${dependency_src}" ] &&
             dependency_src="$(realpath "${dependency_src}")" &&
               dependency_type="${__SBOM__}"
           [ -s "${component}/${dependency_src}" ] && [ -f "${component}/${dependency_src}" ] &&
             dependency_src="$(realpath "${component}/${dependency_src}")" &&
               dependency_type="${__SBOM__}"
           if [[ "${dependency_src^^}" = "${__GITHUB__}" ]]; then
             # at this point not sure of the actual SBOM to be pulled from GHAPI
             dependency_type="${__SBOM__}"
           else
             [[ ! -f "${dependency_src}" ]] && \
               _fatal "expecting SBOM specification at $(realpath "${dependency_src}") or ${component}/${dependency_src}"
           fi
           ;;
         phylum)
           dependency_type="${__PHYLUM__}"
           _doPhylum="true"
           dependency_src="${dependency_src/:phylum/}"
           [[ "${dependency_src}" =~ : ]] && puri="${dependency_src}"
           ;;
         *)
           _fatal "expecting dependency type 'sbom' or 'phylum' but found: '${dependency_src/*:/}'"
           ;;
       esac
       ;;
    U) puri="${OPTARG}"
       dependency_type="${__PHYLUM__}"
       dependency_src="${puri}"
       _doPhylum="true"
       _warn "-U deprecated, please start to use '-P ${puri}:phylum'"
       ;;
    V) echo "Version: ${_version}" && _fatal "" ;;
    W) scoreTimeout="${OPTARG}"
       ! [[ ${scoreTimeout} =~ ^[0-9]+$ ]] && \
         [[ ${scoreTimeout,} != "default" ]] && \
         _fatal "expecting a positive integer for scoreTimeout (${scoreTimeout})"
         [[ ${scoreTimeout,} == "default" ]] && scoreTimeout="${__TIMEOUT__}"
       ;;
    Z) _CAStoreVolume="${OPTARG}"
       _CAStoreDocker="-v ${_CAStoreVolume}:/etc/ssl/certs/ca-certificates.crt"
       ;;
    h|*) cat <<-_OPTSEOF
  USAGE: ${0} analyze [OPTIONS]

  OPTIONS

  -c:  set number of days for cache staleness check (default: ${_cache_days})
  -d:  set depth number on dependencies to dig into (default: ${dependencyDepth}, primary - teritary, or 'all' (no limit))
  -f:  force rebuild (overrides -p) of all or specific(s) caches, scores, reports or other data
       comma separate being ${_bldFlags}
  -h:  this message (and exit)
  -i:  sets the depth for vulnerability discoveries for SBOM project dependency sources (default: ${issueDepth}, top component only, #, 'all' (no limit))
  -l:  log output messages to file of the form 'run-YYYYMMDD-HHMMSS.log' in 'logs' folder
  -o:  build only the BoE (i.e., do nothing else but that, and exit. see -B)
  -p:  protect, no automatic updates (useful for reproducibility)
  -q:  quiet (overrides verbose, warnings)
  -u:  update modifier to force rebuild (preserves information where possible, e.g., deps, subdeps)
  -v:  verbose, not quiet
  -B:  build body of evidence (.tgz) suitable for archive storage
  -C:  set local component name/project name (REQUIRED)
  -D:  set depth on dependencies to run scorecards (default: ${scoreDepth}, top component only, #, or 'all' (no limit))
  -G:  set Github project site (REQUIRED)
  -L:  make one or more subreports and exit (default '${report_type}')
  -O:  offline - do not use networking (some capabilities will be degraded) relies on cached data
  -P:  set project dependency source (github:sbom, <jsonfile>:sbom, <project>:phylum, <uri>:phylum) (REQUIRED)
       (sbom types automatically detected: SPDX, CycloneDX (coming soon))
  -U:  *deprecated* use package URI spec rather than a Phylum.io project name (e.g., npm:@babel/highlight:^7.18.6)
  -V:  display version (and exit)
  -W:  watch docker scorecards run not to exceed time limit (default: ${__TIMEOUT__} seconds)
  -Z:  specify certificates trust store(s) when required by enterprise-level proxies
       which may be in use (e.g. -Z '/etc/ssl/certs/ca-certificates.crt')

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
[[ -n "${__logfil}" ]] && [[ "${__logfil}" =~ ^run ]] && \
        __logger="tee -a ${__logfil}" && \
        date +%s > "${__logfil}" && \
        _rp="$(realpath -e "${__logfil}")" && \
        cp /dev/null "${__logfil}.basherr" && exec 2>"${__logfil}.basherr"

_say "cmdline: ${_cmdline}"

[[ -n "$(ls "${component}"/run-*log 2>/dev/null)" ]] &&
  _fatal "found potentially active runlog(s): '$(ls "${component}"/run-*log)', remove/move if not busy/active"

#
# do any overriders here
#
${protectNoUpdate} && { ${force_rebuild} || ${BFLAGS[job]}; } &&
  _warn "-f overrides (forced job rebuild) -p, automatic updates are re-enabled" &&
  protectNoUpdate="false"

#
# check runtime requirements
#
if ! check_runtime; then _fatal "exiting due to missing or errored runtime requirement(s)"; fi

_say "establishing componment working folder ${component}"
mkdir -p "${_wkgDir}/${component}"

_say "setting current working folder to ${component}"
pushd "${_wkgDir}/${component}" >&"${_fdverbose}" || _fatal "can't set working folder to ${_wkgDir}/${component}"

date +%s > "${__RUNTIME__}" || _fatal "working folder ${_wkgDir}/${component} not writable for $(id)"

#
# since 'preMVP 240507a (branch: main)' tidy
# up all logfiles to a logs folder, work
# legacy runs to this same folder
#
mkdir -p logs/
[[ -d logs ]] && find . -maxdepth 1 -name 'run-*.log' -print0 | xargs -0 -I {} mv {} ./logs/

#
# this log file will be moved later in cleanup
#
[[ -n "${__logfil}" ]] && [[ "${__logfil}" =~ ^run ]] && mv -f "${_rp}" "." && mv -f "${_rp}.basherr" "."

#
# move the sbom here to the working folder
# TODO: only move/overwrite if what's specified is newer
#
[[ "${dependency_type}" == "${__SBOM__}" ]] && {
  _msg="are declared to include transitive dependencies"
  [[ ${issueDepth} == "auto" ]] && issueDepth=0
  [[ "${dependency_src^^}" != "${__GITHUB__}" ]] && cp -a "${dependency_src}" ./ &&
    _msg="are likely not to include transtive dependencies" && issueDepth=1
  dependency_src="$(basename "${dependency_src}")";
  _info "SBOM dependencies in '${dependency_src}' ${_msg} - issue depth is ${issueDepth} (change with -i)"
  unset _msg
}

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
__tmp_dep_graph="$(mktemp -u -p . -t depGraph.XXXXXXXXXX)"
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
__gitcontribcsv=$(basename "${gh_site}")_gitcli_contrib.csv
__sdnDB=sdnDB.json
__ghrcommitjson=$(basename "${gh_site}")_ghapi_commit.json

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
