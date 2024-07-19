# OSS-P4/R

Open Source P4 Tool

Copyright 2024 Carnegie Mellon University.

NO WARRANTY. THIS CARNEGIE MELLON UNIVERSITY AND SOFTWARE ENGINEERING INSTITUTE MATERIAL IS FURNISHED ON AN "AS-IS" BASIS. CARNEGIE MELLON UNIVERSITY MAKES NO WARRANTIES OF ANY KIND, EITHER EXPRESSED OR IMPLIED, AS TO ANY MATTER INCLUDING, BUT NOT LIMITED TO, WARRANTY OF FITNESS FOR PURPOSE OR MERCHANTABILITY, EXCLUSIVITY, OR RESULTS OBTAINED FROM USE OF THE MATERIAL. CARNEGIE MELLON UNIVERSITY DOES NOT MAKE ANY WARRANTY OF ANY KIND WITH RESPECT TO FREEDOM FROM PATENT, TRADEMARK, OR COPYRIGHT INFRINGEMENT.

Licensed under a MIT-style license, please see license.txt or contact permission@sei.cmu.edu for full terms.

[DISTRIBUTION STATEMENT A] This material has been approved for public release and unlimited distribution.  Please see Copyright notice for non-US Government use and distribution.

This Software includes and/or makes use of Third-Party Software each subject to its own license.

DM24-0786

Applies to ```pubRel 240719a (branch: publicRelease)``` versions or later.

## DESCRIPTION

Open Source Software Project, Product, Protection, and Policy Report

## SYNOPSIS
```
+--------------------+         +================+         +==================+
| Analyze Package(s) | ------> | Make an OSS-P4 | ------> | Publish OSS-P4/R |
| with Phylum.io.    |         | Report         |         | to Confluence    |
+--------------------+         +================+         +==================+

* --> (progresses from (left) to (right))
        (1)                            (2)                         (3)
```
(1) See ```docs/``` folder in this repo for examples on various methods to perform analysis
(2) & (3) Are covered here.

Essentially, ```scir-oss.sh```, (2), Invokes tools and queries data from public and proprietary sources to obtain indicators related to stakeholder concerns on the use of specific open source software products, produced by open source projects using various processes, tools, and methods to protect the integrity of those product(s) produced by the open source projects and along with policies enacted by those projects which may be impactful to the use (or consumption) of a specific open source product. Hence, Open Source Software Project, Product, Protection, and Policy Report (OSS-P4/R)

After obtaining those indicators, ```scir-oss.sh```:
* Correlates results according to stakeholder criteria
* Flags potential concerns based on MY thresholds and goals
* Normalizes scoring and rolls up results
  * 4 “P(s)”
  * DoD CIO’s criteria

Reports can also be published to Confluence via ```pub-scir.sh```, (3).

## QUICK START

### Download
```
git clone https://github.com/cmu-sei/scir-oss.git
git remote -v
origin	https://github.com/cmu-sei/scir-oss.git (fetch)
origin	https://github.com/cmu-sei/scir-oss.git (push)
```
### Command line

#### scir-oss: Make an OSS-P4/R
```
$ cd scir-oss
$ ./scir-oss.sh -h
  USAGE: ./scir-oss.sh [OPTIONS]

  OPTIONS

  -c:  set number of days for cache staleness check (default: 2)
  -f:  force rebuild (overrides -p) of all or specific(s) caches, scores, reports or other data
       comma separate being 'all', or one or more of: cards,caches,deps,subdeps,meta,crit,scard,hcheck,scores,issues,job
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
  -W:  watch docker scorecards run not to exceed time limit (default: 300 seconds)

  BUILD FLAGS (-f 'flag1[,flag2,...]')

  all:		acts as if all BUILD FLAGS are true, essentially rebuilds everything from scratch (logs retained)
  caches:	cached data from github (home page, contributors, SBOM), phylum project data
  cards:	forces all scorecards and checks to run and retry previous error, no cached data is changed
  crit:		forces OSSF Criticality Score to refresh
  deps:		rebuilds all primary dependencies
  hcheck:	forces MITRE Hipcheck to refresh
  issues:	rebuilds phylum issues from all dependencies
  job:		rechecks phylum analysis job for updates
  meta:		forces GitHub Metadata to refresh
  scard:	forces OSSF Scorecard to refresh
  scores:	rebuilds coalesced scores from all scorecards and checks
  subdeps:	rebuilds all tertiary and deeper dependencies
```
Explaination: TBD

#### pub-scir: Publish an OSS-P4/R to Confluence
$ cd scir-oss
$ ./pub-scir.sh -h
```
  USAGE: ./pub-scir.sh [OPTIONS]

  OPTIONS

  -a:  file to attach to the page (e.g., body of evidence)
  -h:  this message (and exit)
  -l:  log output messages to file of the form 'pub-YYYYMMDD-HHMMSS.log' in 'logs' folder
  -o:  attach file only without changing page itself
  -p:  preserve local working files and responses (for testing)
  -q:  quiet (overrides verbose, warnings)
  -v:  verbose, not quiet
  -A:  Ancestor page title (default: 'Example OSS Reports')
  -C:  set local component name/project name (REQUIRED)
  -S:  Space in Confluence (default: MYDOCS)
  -T:  Page Title (default: same as -C with ' auto' appended)
  -V:  display version (and exit)
```
Explaination: TBD

### Use Cases

#### A complete OSS project on GitHub previously analyzed by Phylum.io
* To make an OSS-P4/R
```
./scir-oss.sh -l -v -D all -B -C fleetth -G fleetdm/fleet
```
* To publish that OSS-P4/R
```
./pub-scir.sh -l -v -C fleetth -T 'Fleet TH' -S MYDOCS -A 'Scratch Test Area'
```

#### A made-up (local) project previously analyzed by Phylum.io (not on GitHub)
* To make an OSS-P4/R
```
./scir-oss.sh -C jray
```
* To publish that OSS-P4/R
```
./pub-scir.sh -C jray -T 'jray (a deep-dive into JFrog Xray)' -S MYDOCS -A 'Scratch Test Area'
```

#### A known package URI which is on GitHub (helpful if it is known to be on Phylum)
* To make an OSS-P4/R
```
./scir-oss.sh -C myany -G chrunlee/anywhere-auth -U 'npm:anywhere-auth:1.0.2'
```
* To publish that OSS-P4/R
```
./pub-scir.sh -C myany -S MYDOCS -A 'Scratch Test Area'
```

#### Produce and archive the Body of Evidence in the OSS-P4/R production
* To produce the BoE
```
./scir-oss.sh -o -B -C fleetth -G fleetdm/fleet
```
* To archive/publish that BoE
```
./pub-scir.sh -C fleetth -T fleet -C fleetth -T 'Fleet TH' -S MYDOCS -A 'Scratch Test Area' -o -a fleetth-scir-p4r-boe_sha256:<insert specific hash>.tgz
```
### Example
#### Generated Files

```
$ ls -ltr fleetth/
total 28476
-rw-r--r-- 1 user group    6986 mmm dd hh:mm fleet_ghapi.json
-rw-r--r-- 1 user group  188601 mmm dd hh:mm fleet_ghapi_contrib.json
-rw-r--r-- 1 user group    3156 mmm dd hh:mm phylum_prjs.json
drwxr-xr-x 1 user group   57760 mmm dd hh:mm subdeps.d
drwxr-xr-x 1 user group      96 mmm dd hh:mm deps.d
-rw-r--r-- 1 user group     494 mmm dd hh:mm fleetth_coalesce.csv
-rw-r--r-- 1 user group  974697 mmm dd hh:mm fleetth_allIssues.json
-rw-r--r-- 1 user group       4 mmm dd hh:mm fleet_ghapi_sbom.json
-rw-r--r-- 1 user group  448453 mmm dd hh:mm fleet_gh.html
-rw-r--r-- 1 user group  359675 mmm dd hh:mm fleetth_job_<jobID>.json
-rw-r--r-- 1 user group 2096129 mmm dd hh:mm fleetth_dep_digraph.txt
-rw-r--r-- 1 user group 2096129 mmm dd hh:mm fleetth_dep_prds.json
-rw-r--r-- 1 user group  136790 mmm dd hh:mm fleetth_dep_prjs.csv
-rw-r--r-- 1 user group  267448 mmm dd hh:mm fleetth_vulmalrep.html
-rw-r--r-- 1 user group   35917 mmm dd hh:mm fleetth_scir.json
-rw-r--r-- 1 user group   31383 mmm dd hh:mm fleetth_scir.html
-rw-r--r-- 1 user group 7398096 mmm dd hh:mm fleetth-scir-p4r-boe_sha256:<sha256sum>.tgz
drwxr-xr-x 1 user group     320 mmm dd hh:mm logs
drwxr-xr-x 1 user group    2080 mmm dd hh:mm oldjobs
```

#### Explaination: The files
##### Cache files

- ```_gh.html``` is the html page of the repo used to find badges and other information
- ```_ghapi.json``` is the GitHub API summary data for the GitHub Project (e.g. ```:repo``` in ```:owner/:repo```)
- ```_ghapi_contrib.json``` is the named contributors to the GitHub Project (limited to 500 entries)
- ```_ghapi_sbom.json``` is the SBOM generated by GitHub dependency graph API, includes CI/CD tools
- ```phylum_prjs.json``` is the list of all the Phylum.io projects analyzed for the ```bearer``` token (will be moved soon)
- ```_dep_digraph.txt``` is the dependency graph of all products in Graphviz format
- ```_dep_prds.json``` is the list of all the dependency products for the Phylum.io analyzed project
- ```_dep_prjs.csv``` is the list of all the OSS Projects that produce those dependant products
- ```_job_<jobID>.json``` is the state of the Phylum.io analysis job
- ```logs/``` folder containing all the runs (```run-*logs.txt```) and pubs (```pub-*logs.txt```) for the report
- ```oldjobs/``` backup/history for prior job status (Phylum will re-run analyzes on the backend without prompting)

##### Dependencies and score cards

```
+================+         +===============+         +============+                 +---> *_ghapi.json
|                | <------ |               | <------ |            |                 |
| _dep_prds.json |         | _dep_prjs.csv |    |    |    deps.d/ |----:owner/:repo-+---> *.sc.json, *.cs.json
|                |         |               |    |    |            |                 |
+================+         +===============+    |    +============+                 +---> *.hc.json
                                                |
                                                |    +============+
                                                |    |            |
                                                +--- | subdeps.d/ |-----:purl-----> *_deps.json
                                                     |            |
                                                     +============+
* <-- ((right) depends on (left))
* --- :(argument) --> ((argument) used to produce (file(s)) (see Interfaces below))
```

The ***world*** starts with ```_dep_prds.json``` (above), here all the primary dependencies are contained within this file using the following:
- ```cat _dep_prds.json | jq -r '.' '.dependencies[]|[.id,.repoUrl]|@csv'```
Example: ```"golang:github.com/golang/protobuf:v1.4.2","https://github.com/golang/protobuf"```

This list of component IDs (```.id```) and home CVS repos (```.repoUrl```) are used to populate ```_dep_prjs.csv``` having the form:
- column 1: level of a dependency graph the component was found (0 being root, 1 being direct descendant of 0, and so on)
- column 2: id (```.id``` from ```_dep_prds.json```)
- column 3: dependency which is essentially column 2 cut at the first ```:``` and everything after (it is a mess and is not used and likely garbage)
- column 4: home repo confirmed either by ```_dep_prds.json``` or discovered by digging on the ecosystem package manager (e.g., maven, golang, npm) (not 100% complete for all ecosystems and possible package managers)
- column 5: 000 (root component given on command line), 100 (found through ```_dep_prds.json```); 200 (found through discoverd and dep successfully downloaded), 404 (found byt no deps downloaded - perhaps bad purl)
Example: ```1,golang:github.com/golang/protobuf:v1.4.2,github.com/golang/protobuf,github.com/golang/protobuf,100```

###### Folder ```deps.d``` is the primary dependencies (level 0, 1)
Here, mangled names are simply a subsitution of the slash (```/```) for underscores (```___```) as in ```:owner/:repo``` is mangled to ```:owner___:repo```
- json key/value: ```"repoUrl": "https://github.com/golang/protobuf" ``` (or otherwise discoveed at runtime)
is mangled to
- ```golang___protobuf```

All are contained in the ```deps.d``` (dependencies) folder by their mangled ```:owner/:repo``` GitHub name
- meta information generated by GitHub end in ```_ghapi.json```
- score cards generated by OSSF/criticality score tool end in ```.cs.json``` (not for all yet)
- score cards generated by OSSF/scorecard tool end in ```.sc.json```
- score cards generated by MITRE/hipcheck tool end in ```.hc.json```

###### Folder ```subdeps.d``` is the sub dependencies to the primary dependencies (levels 2 and beyond)
Here, names similarly mangled, but now include the language ecosystem/package manager and version number. Example:
- json key/value: ```"purl": "pkg:golang/google.golang.org/protobuf@v1.28.1"```
is mangled to 
- ```golang:google.golang.org___protobuf:v1.28.1```

These folders contain the level 2 and beyond package dependencies and end in ```_deps.json```

##### Interfaces and files (by files)
* ```_gh.html```
  - command line tool: ```curl```
  - URI: ```github.com/:owner/:repo```
  - Purpose: to scrape page to obtain potential badges for SLSA.
* ```_ghapi.json```
  - command line tool: ```curl```
  - URI: ```api.github.com/repos/:owner/:repo```
  - Purpose: to obtain various aspects of the comonent project hosted on GitHub for the report.
* ```_ghapi_contrib.json```
  - command line tool: ```curl```
  - URI: ```api.github.com/repos/:owner/:repo/contributors```
  - Purpose: to obtain the list and count of contributors to the hoste GitHub project.
* ```_ghapi_sbom.json```
  - command line tool: ```curl```
  - URI: ```api.github.com/repos/:owner/:repo/dependency-graph/sbom```
  - Purpose: to obtain the project's product's SBOM.
* ```phylum_prjs.json```
  - command line tool: ```curl```
  - URI: ```api.phylum.io/api/v0/projects/```
  - Purpose: to obtain the list of all the phylum.io projects submitted to phylum.io for analysis.
* ```_dep_prds.json```
  - command line tool: ```curl```
  - URI: ```api.phylum.io/api/v0/data/[projects|packages]/:prjid```
  - Purpose: to obtain phylum.io primary project or primary package details and its dependencies.
* ```_dep_prjs.csv```
  - command line tool: ```curl```
  - URI: ```api.phylum.io/api/v0/data/packages/:puri```
  - Purpose: to obtain phylum.io sub-dependency package details and, further, its dependencies.
  - command line tool: ```curl```
  - URI: ```<site>/:repoUrl```
    - where ```<site>``` is one of ```google.golang.org```, ```golang.org```, ```go.opentelemetry.io```, ```go.elastic.co```, ```cloud.google.com/go```, ```go.uber.org```, ```gotest.tools```, ```go.opencensus.io```, ```go.mozilla.org```, ```gopkg.in```, ```gocloud.dev```
  - Purpose: to scrape reported ```:repoUrl``` for repo/VCS for package's project home.
* ```_job_<jobID>.json```
  - command line tool: ```curl```
  - URI: ```api.phylum.io/api/v0/data/jobs/:jobid```
  - Purpose: to obtain the status of the phylum.io analysis (component or incomplete) as well as other analysis results.
* ```*.sc.json```
  - command line tool: ```scorecard```
  - URI: various
  - Purpose: to run and obtain OSSF Scorecard check scores.
* ```*.cs.json```
  - command line tool: ```criticality_score```
  - URI: various
  - Purpose: to run and obtain OSSF Criticality Score results.
* ```*.hc.json```
  - command line tool: ```hipcheck```
  - URI: various
  - Purpose: to run and obtain MITRE's hipcheck analysis results.
* all (to GitHub)
  - command line tool: ```scorecard```, ```criticality_score```, ```hipcheck```, and ```curl```
  - URI: ```api.github.com/user/octocat```
  - Purpose: to manage token rate limits imposed by GitHub API.
* all (to phylum)
  - command line tool: ```phylum```
  - URI: unknown by way of ```phylum auth token -qq --bearer```
  - Purpose: to obtain and authorize Phylum.io's API
* other (for GitHub Organization Owner)
  - command line tool: ```curl```
  - URI: ```api.github.com/user/:owner```
  - Purpose: to obtain specific user or organizational details for a specific GitHub repo.

##### Summaries

- ```_coalesce.csv``` is the aggregation (vertically) of all the score card scores (horizontally)
- ```_scir.json``` is the answers to the OSS-P4/R template in confluence for the GitHub Project
- ```_allIssues.json``` is the concatenation of all the Phylum.io issues in one ```json``` for for report writing

##### Snippets for Confluence
- ```_vulmalrep.html```
- ```_scir.html```

##### BoE
- ```-scir-p4r-boe_sha256:<hash value>.tgz``` is the tarball of 'The Files' (listed here)

#### Command line Args ```scir-oss.sh``` (some described)

##### (```-p```) Protect

##### (```-L```) (Re-)Run Issue(s) Report
select which reports to (re-)generate, currently ```'all'``` is the only report to select. TODO: will be comma separated list among ```'vuls'```, ```'malcode'```, ```'author'```, ```'badcode'```, ```'license'```, or ```'none'```.
##### (```-W```) Watch
watchdog to terminate docker containers that run longer that specified seconds (default is 300) as a means to guard against containers may be "stuck" or run for too long (for instance, running ```hipcheck``` on the linux kernel github repo can take over an hour)

#### Command line Args ```pub-scir.sh```


## Rebuilding

- to rebuild everything, use the ```-f all``` flag for ```scir-oss.sh```

For selective rebuilding:

- to rebuild only the ```_scir.json```, delete the file
- to rebuild only the ```_coalesce.csv```, delete the file (or ```-f scores```)
- to rebuild ```dep_prds.json``` and ```dep_prjs.csv```, delete either file (or ```-f deps```)
- to rebuild all the score cards, remove the ```deps.d``` folder (completely) (or ```-f scard,hcheck,crit,meta```)
- to rebuild all the score cards for a specific project, remove the ```deps.d/<project>``` folder (and use ```-f cards```)
- to rebuild a OSSF/scorecard for a specific project, remove the ```deps.d/<project>/_sc.json``` file (and use ```-f cards```)
- to rebuild a OSSF/Criticality Score card for a specific project, remove the ```deps.d/<project>/_cs.json``` file (and use ```-f cards```)
- to rebuild a MITRE/hipcheck card for a specific project, remove the ```deps.d/<project>/_hc.json``` file (and use ```-f cards```)
- to rebuild a GH metafile card for a specific project, remove the ```deps.d/<project>/_ghapi.json``` file (and use ```-f cards```)

For selective "skipping":

- ```.skip``` files will override rebuilding for individual score card files, e.g., ```.sc.json.skip```, ```.cs.json.skip```, ```.hc.json.skip```, or ```_ghapi.json.skip```, which is useful when the tool is erroring on that dependent project

```
WARNING: hipcheck skipping aws/aws-sdk-go-v2, del deps.d/aws___aws-sdk-go-v2/aws___aws-sdk-go-v2.hc.json.skip to undo
```


## Requirements

### Phylum.io analysis

Explaination: TBD

### scir-oss.sh binaries

```
bash (version >= 5.0)
jq-1.6
criticality_score v1.0.8
curl 7.68.0
Docker version 20.10.12
base64 (GNU coreutils) 8.30
phylum v5.9.0
iconv (GNU libiconv 1.11)
sha256sum (GNU coreutils) 8.30
tar (GNU tar) 1.30
```

### pub-scir.sh binaries

```
bash (version >= 5.0)
jq-1.6
curl 7.68.0
```

### docker images

```
gcr.io/openssf/scorecard:latest
hipcheck:2022-07-06-delivery
```

### Environment and Personal Access Tokens

* Phylum.io account
The two following command should succeed before using ```scir-oss.sh```
```
phylum auth status
✅ Currently authenticated as 'shissam@sei.cmu.edu' with long lived refresh token
phylum auth token --bearer
eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSl... (truncated here)
```

* GitHub account
```
GITHUB_AUTH_TOKEN
```
```
HC_GITHUB_TOKEN
```

* Confluence account
```
CONF_PAT
```

## Code Structure

### scir-oss.sh

This script is logically structured into two general phases, build and report. Build is the execution of external tools and APIs to collect data from a variety of public and proprietary sources. Once, collected, that data is categorized, mathematically normalized, and summerized into a report suitable for review on Confluence.

The code is contained in a singular `bash` shell script containing a little over 100 functions. Further, the code is checked using [`shellcheck`](https://github.com/koalaman/shellcheck) to ensure some semblence of correctness. Furthermore, the script [`shell-call-graph`](https://codeberg.org/rak/shell-call-graph) is used to structurally graph these 100+ functions. For "saneness", the following three call graphs seem to be the most helpful.

NB: either install `dot` to convert digraphs to PDF (or other formats), or use the online tool [Graphviz Online](https://dreampuf.github.io/GraphvizOnline/) by way of copy/paste (the generated `.txt` file)

#### full call graph

```
# generate graph
bash /home/vagrant/src/shell-call-graph/shell-call-graph ./scir-oss.sh > scir-full-digraph.txt
#
# create a PDF of the graph
cat scir-full-digraph.txt | dot -Tpdf > scir-full-digraph.pdf
```

#### build call graph

```
cat scir-full-digraph.txt | \
  grep -v -E '(_compile_json_p4report|_cio_criteria|_p4_outlook|_summary_scores_criteria_tbl|_summary_scores)' | \
  grep -v -E '(_say|_warn|_debug|_fatal|_err)' > scir-build-digraph.txt

cat scir-build-digraph.txt | dot -Tpdf > scir-build-digraph.pdf
```

#### report call graph

```
cat scir-full-digraph.txt | \
  grep    -E '({|}|_compile_json_p4report|_cio_criteria|_p4_outlook|_summary_scores_criteria_tbl|_summary_scores)' | \
  grep -v -E '(_dig4subdep|_phylum_dep_components|build_caches|_say|_warn|_debug|_fatal|_err)' > scir-report-digraph.txt

cat scir-report-digraph.txt | dot -Tpdf > scir-report-digraph.pdf
```

### pub-scir.sh

```
bash /home/vagrant/src/shell-call-graph/shell-call-graph ./pub-scir.sh > pub-full-digraph.txt
cat pub-full-digraph.txt | dot -Tpdf > pub-full-digraph.pdf
```

## TODOs

Tagged in the scripts as TODO:
