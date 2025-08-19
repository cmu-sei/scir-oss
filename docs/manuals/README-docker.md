# OSS-P4/R Docker Installation

## Recommended Procedure

### `git` the code

```bash
git clone https://github.com/cmu-sei/scir-oss.git
cd scir-oss
#
# build criticality_score since OSSF does not have a pre-built container
# the criticality_score executable is copied from this container into the
# next built OSS-P4/R container
#
git clone https://github.com/ossf/criticality_score.git
cd criticality_score
docker build -f ../Dockerfile.criticality_score -t cmu-sei/criticality_score:dev .
docker images | grep -E '(REPOSITORY|cmu-sei/criticality_score)'
REPOSITORY                    TAG     IMAGE ID       CREATED         SIZE
cmu-sei/criticality_score     dev     004b13def645   4 weeks ago     102MB
cd ..
#
# now build the OSS-P4/R container
#
docker build -f ./Dockerfile.p4-prod -t cmu-sei/scir-oss:prod .
docker images | grep -E '(REPOSITORY|cmu-sei/scir-oss)'
REPOSITORY                    TAG     IMAGE ID       CREATED         SIZE
cmu-sei/scir-oss              prod    bf55152dc404   28 minutes ago  744MB
```

### docker volumes

```bash
#
# persistent OSS-P4/R working volume
# must be read-write for UID 1001 and GID 1001
# *required* for analyzing and publishing over time
#
# the volume target must be '/app/oss-p4r'
#
  -v ~/p4wkg:/app/oss-p4r
#
# persistent grype working volume
# *highly recommended* for increased performance over time
#
  -v ~/p4wkg/cache/grype:/home/hc_user/.cache/grype
#
# persistent hipcheck cache for git clones
# *recommended* for increased performance over time
#
  -v ~/p4wkg/cache/hipcheck:/home/hc_user/.cache/hipcheck
#
# imported SBOM (see -P <jsonfile>:sbom)
# *optionally required* if an SBOM file is provided
# -v <>:/app/<>
# e.g. -v ~/p4wkg/oparest.spdx.json:/app/oparest.spdx.json
#
  -v ~/p4wkg/cache/phylum/settings.yaml:/home/hc_user/.config/phylum/settings.yaml
#
# persistent phylum API key and settings
# *optionally required* if phylum CLI is to be used
# -v /dev/null:/home/hc_user/.config/phylum/settings.yaml 
# can be used as a place holder
# 
  -v ~/p4wkg/cache/phylum/settings.yaml:/home/hc_user/.config/phylum/settings.yaml
```

### docker environment

```bash
#
# *required* for OSSF scorecard, criticality_score, and OSS-P4/R use of GitHub API
#
  -e GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN}
#
# *required* for hipcheck
#
  -e HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN}
#
# *required* Confluence API Token for read/write access to Confluence Server
#
  -e CONF_PAT=${CONF_PAT}
#
# *optional* over-ride of Confluence Server address in localizations
#
  -e _LOCAL_CONFSVR=https://confluence.example.com
```
## Example Setup
```bash
#
# make working volume folder and cache folders
#
mkdir -p ~/p4wkg/cache/grype ~/p4wkg/cache/hipcheck
sudo chown -R 1001:1001 ~/p4wkg

#
# confirm docker build
#
$ docker run --rm cmu-sei/scir-oss:prod analyze -V
Version: pubRel 250516evie (branch: publicRelease)

$ docker run --rm -e _LOCAL_CONFSVR=https://confluence.example.com cmu-sei/scir-oss:prod publish -V
Version: pubRel 250417a (branch: publicRelease) for Server at https://confluence.example.com

#
# pre-build grype cache
#
$ docker run --rm --entrypoint=/home/hc_user/.local/bin/grype cmu-sei/scir-oss:prod --version
grype 0.92.2

$ docker run --rm -v ~/p4wkg/cache/grype:/home/hc_user/.cache/grype -v ~/p4wkg/cache/hipcheck:/home/hc_user/.cache/hipcheck --entrypoint=/home/hc_user/.local/bin/grype cmu-sei/scir-oss:prod db update
Vulnerability database updated to latest version!

$ docker run --rm -v ~/p4wkg/cache/grype:/home/hc_user/.cache/grype -v ~/p4wkg/cache/hipcheck:/home/hc_user/.cache/hipcheck -e GRYPE_DB_VALIDATE_AGE=false --entrypoint=/home/hc_user/.local/bin/grype cmu-sei/scir-oss:prod db status -o json
{
 "schemaVersion": "v6.0.2",
 "from": "https://grype.anchore.io/databases/v6/vulnerability-db_v6.0.2_2025-06-04T01:32:23Z_1749035557.tar.zst?checksum=sha256%3A77238f4ffbc7cf72bf4dedabbb21a3d0dd3ade90fb5d9df7c4da2870f8d1a9b7",
 "built": "2025-06-04T11:12:37Z",
 "path": "/home/hc_user/.cache/grype/db/6/vulnerability.db",
 "valid": true
}

```

## Example Analyze (SCIR-OSS)

```bash
$ docker run --rm \
  -e GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN} \
  -e HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN} \
  -v ~/p4wkg:/app/oss-p4r \
  -v /dev/null:/home/hc_user/.config/phylum/settings.yaml \
  -v ~/p4wkg/cache/grype:/home/hc_user/.cache/grype \
  -v ~/p4wkg/cache/hipcheck:/home/hc_user/.cache/hipcheck \
  cmu-sei/scir-oss:prod analyze -l -v -C oparest -G go-training/opa-restful -P github:sbom
```

## Example Publish (PUB-SCIR)

```bash
$ docker run --rm \
  -e _LOCAL_CONFSVR=https://confluence.example.com \
  -e CONF_PAT=${CONF_PAT} \
  -e GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN} \
  -e HC_GITHUB_TOKEN=${GITHUB_AUTH_TOKEN}   \
  -v ~/p4wkg:/app/oss-p4r   \
  -v /dev/null:/home/hc_user/.config/phylum/settings.yaml   \
  -v ~/p4wkg/cache/grype:/home/hc_user/.cache/grype   \
  -v ~/p4wkg/cache/hipcheck:/home/hc_user/.cache/hipcheck \
  cmu-sei/scir-oss:prod publish -l -v -C oparest -T 'OPA Rest API SBOM' -S MYDOCS -A 'OSS-P4/R Reports'
```