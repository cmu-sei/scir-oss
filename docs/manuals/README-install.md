# OSS-P4/R Installation

## Prerequisites

```
bash (version >= 5.0)
jq-1.6
curl 7.68.0
Docker version 20.10.12
base64 (GNU coreutils) 8.30
iconv (GNU libiconv 1.11)
sha256sum (GNU coreutils) 8.30
tar (GNU tar) 1.30
```

```bash
# for debian-based systems:
apt install -y build-essential docker docker-compose apt-transport-https unzip jq curl bc
#
# likely need to re-login after this step
#
usermod -aG docker vagrant
```

### Optional

```
criticality_score v1.0.8 [1]
grype 0.91.0 [2]
phylum v7.3.0 [3]
```
[1] To get OSSF's Criticality Score for the project (see `-G` command line option). [OSSF Criticality Score Install](https://github.com/ossf/criticality_score)

[2] To find issues based on SBOM packages (see `-P` command line option). [Anchore Grype Install](https://github.com/anchore/grype)

[3] Only when using Phylum.io/Veracode service (see `-P` command line option). [Phylum.io CLI Install](https://github.com/phylum-dev/cli)

## Recommended Procedure

### `git` the code

```bash
git clone https://github.com/cmu-sei/scir-oss.git
```

### `cp` to local bin

```bash
mkdir -p ~/.local/bin
cp -i scir-oss/scir-oss.sh ~/.local/bin/
cp -i scir-oss/pub-scir.sh ~/.local/bin/
cp -i -r scir-oss/settings/ ~/.local/bin/
export PATH="~/.local/bin:${PATH}"
```

### Perform Localizations

#### SCIR-OSS Runtime

Likely necessary, especially for PATHs. Found in ```<installpath>/settings/scir-oss/localizations.lib.sh```

Specify which ```docker``` containers (or equivalent binaries) to use.
```bash
#
# use docker hub and OSSF images
#
_LOCAL_OSSFSC="gcr.io/openssf/scorecard:latest"
_LOCAL_OSSFCS="${HOME}/go/bin/criticality_score"
_LOCAL_MITRHC="mitre/hipcheck:latest"
```

#### SCIR-OSS Report Writing

Probably not necessary. Found in ```<installpath>/settings/scir-oss/reportWriter_criteria_desc_lib.sh.<language>```

Specify labels and descriptions for the final ```.json```, ```.html```, and ```.md``` report.
```bash
_LOCAL_ABANDONED_PROJECTS_DESC="Projects identified, explicitly by way of OSSF Scorecard and/or GitHub's API as being marked as archived"
_LOCAL_ABANDONED_PROJECTS_ID="Abandoned_Projects"
_LOCAL_ABANDONED_PROJECTS_LABEL="Number of Abandoned Project(s)"
_LOCAL_ABANDONED_PROJECTS_RISK="abandoned projects may have faults and vulnerabilities that may never by fixed"
```

#### PUB-SCIR Runtime

Very likely necessary if you intend to use Altassian's Confluence. Found in ```<installpath>)/settings/pub-scir/localizations.lib.sh```

Specify defaults for the Altassan Confluence Server, Confluence Space Key, and Ancestor Title
```bash
_LOCAL_CONFSVR="https://confluence.myhost.example.com"
_LOCAL_spaceKey="MYDOCS"
_LOCAL_ancestorTitle="OSS-P4 Reports"
```

### docker images and binaries

```
gcr.io/openssf/scorecard:latest
mitre/hipcheck:latest (version 3.3.1) or hipcheck:2022-07-06-delivery (version 3.1.0)
```

### Plugins

As of December 2025, a small handful of analyzes were turned into plugins, specifically:
* Problem Reporting (`pReport`)
* Abandoned Projects (`pAbandon`)
* Anonymous Authors (`anony`)
* Affiliated Authors (`affil`)

These Plugins are sensed and loaded at runtime from the `settings/scir-oss/plugins` folder (typically).

#### Affiliated Authors

This specific plugin is an improved affiliation analysis provided by `Hipcheck v3.14`. For non-docker SCIR-OSS containers (see `README-docker.md`), this particular version of `Hipcheck` needs to be installed for this plugin to operate. This is the recommended procedure for installing that affiliation helper:

```bash
$ HC_AFFILIATION_VERSION="3.14.0"
$ curl -sSfL https://github.com/mitre/hipcheck/releases/download/hipcheck-v${HC_AFFILIATION_VERSION}/hipcheck-x86_64-unknown-linux-gnu.tar.xz -o hipcheck-x86_64-unknown-linux-gnu.tar.xz 
$ curl -sSfL https://github.com/mitre/hipcheck/releases/download/hipcheck-v${HC_AFFILIATION_VERSION}/hipcheck-x86_64-unknown-linux-gnu.tar.xz.sha256 -o hipcheck-x86_64-unknown-linux-gnu.tar.xz.sha256
$ sha256sum -c --strict hipcheck-x86_64-unknown-linux-gnu.tar.xz.sha256 --ignore-missing
#
# if sha256sum passes, continue
#
$ tar xf hipcheck-x86_64-unknown-linux-gnu.tar.xz --strip-components 1 -C /tmp/ hipcheck-x86_64-unknown-linux-gnu/hc
$ mv -v /tmp/hc ${HOME}/.local/bin/hc-affiliation
$ rm -f hipcheck-x86_64-unknown-linux-gnu.tar.xz hipcheck-x86_64-unknown-linux-gnu.tar.xz.sha256
#
# to test hc-affiliation
# (it is assumed that hc-affiliation is in $PATH)
#
$ command -v hc-affiliation
/home/vagrant/.local/bin/hc-affiliation
#
# a config.json file in 
# settings/scir-oss/plugins/affil_plugin/
# can be used to change the default path for hc-affiliation if needed
$ hc-affiliation --policy ./settings/hipcheck314/config/Hipcheck.kdl ready
                Done loading policy and data files (0 seconds)
              Config using policy located at ./settings/hipcheck314/config/Hipcheck.kdl
                Done loading exec config (0 seconds)
                Done starting plugins (2 seconds)
Hipcheck Version: hipcheck 3.14.0
Git Version:      git version 2.46.2
NPM Version:      10.9.2
Cache Path:       /home/vagrant/.cache/hipcheck
Policy Path:      ./settings/hipcheck314/config/Hipcheck.kdl
Plugins:          All started successfully
Hipcheck is ready to run!
#
# here ./settings/hipcheck314/config/Hipcheck.kdl is included in the git clone of cmu-sei/scir-oss
#
```

### Required Personal Access Tokens

* Phylum.io account
The two following command should succeed before using ```scir-oss.sh``` with Phylum.io projects (see `-P` command line option)
```
phylum auth status
✅ Currently authenticated as 'shissam@sei.cmu.edu' with long lived refresh token
phylum auth token --bearer
eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSl... (truncated here)
```

* GitHub account
```bash
export GITHUB_AUTH_TOKEN="..."
```
```bash
export HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN}
```

* Atlassian Confluence account
```bash
export CONF_PAT="..."
```