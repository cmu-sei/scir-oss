# OSS-P4/R Installation

## Prerequists

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