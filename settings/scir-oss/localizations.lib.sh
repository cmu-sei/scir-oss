# use local nomenclature
_LOCAL_VERSION="preMVP 250310a (branch: main)"
#
# use docker hub and OSSF images
#
_LOCAL_OSSFSC="${_LOCAL_OSSFSC:-gcr.io/openssf/scorecard:latest}"
_LOCAL_OSSFCS="${_LOCAL_OSSFCS:-${HOME}/go/bin/criticality_score}"
_LOCAL_MITRHC="${_LOCAL_MITRHC:-mitre/hipcheck:latest}"
#
# criteria description
#
_LOCAL_LANG=${_LOCAL_LANG:-en}
_LOCAL_CRITERIA_DESC="${_LOCAL_CRITERIA_DESC:-reportWriter_criteria_desc.lib.sh.${_LOCAL_LANG}}"
