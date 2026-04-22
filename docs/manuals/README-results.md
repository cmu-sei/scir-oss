# OSS-P4/R Report Interpretation
The Open Source Software Project, Product, Protections, and Policy Report can be
intimitating to interpret due to the sheer volume of information that is
analyzed in order to create it. Here we will demystify the content and break
down the report to explain what each section is focusing on and how the information
and/or scores in each should be interpreted and responded to.

## General Conventions
The report uses a small number of conventions that are consistent across the report.

### Scoring
The OSS-P4/R report adopts a 0.0-10.0 scoring methodology with 10 representing the lowest measured risk,
and 0.0 representing the highest measured risk. If a score cannot be determined due to an error or lack
of information, NaN (Not a Number) might be displayed.

#### Thresholds
Generally speaking, the following thresholds apply:

| Threshold | Risk Assessment  |
| --------- | ---------------- |
| 8.0-10.0  | Low Risk         |
| 7.0-7.9   | Medium-low Risk  |
| 5.0-6.9   | Medium Risk      |
| 4.0-4.9   | Medium-high Risk |
| 0.0-3.9   | High Risk        |

### Iconography
The report uses two icons for readers to quickly identify issues with the report:

![Error](/docs/assets/error.svg) The error icon indicates a finding that the report reader needs to respond to.

![Warning](/docs/assets/warning.svg) The warning icon indicates that an error with the tool(s) was encountered.
If you believe the error is substantive (e.g. something that shouldn't have happended), report the issue to the
OSS-P4/R maintainers.

# Responding to a Report
The first time a report is run on a project it may surface a lot of potential findings that can
seem overwhelming at first. Not all potential findings are applicable as some checks and
scoring is heuristic and the tools are not perfect. Generally speaking, the report should
be approached in such a way:

1. Approach the report holistically. The goal is to reduce overall risk, not optimize for a certain score.
2. Start in areas of the report that flag the highest risk factors first. If high risks are surfaced, 
start there before moving to lower risk areas.
3. If the team has established processes for dealing with certain findings, like vulnerabilities, 
continue to follow those processes. The tools that OSS-P4/R uses might not be as comprehensive as others
that the team uses. Bear that in mind, findings such as vulnerabilities are subject to a large number of
false positives.
4. Focus on areas of the report that are novel, that is checks that may not be covered by other tools
in the pipeline.
5. Review findings, understand what they mean (refer to tool documentation if needed), and use the 
Avoid, Mitigate, Transfer, Accept process for deciding how to address findings.
6. Prioritize and schedule changes needed to handle findings.
7. Periodically re-run the report to pull in fresh information for the project and dependencies and 
repeat the process.

# Report Breakdown
The report contains the following sections:

1. Overview information and links to critical and high vulnerabilities at the end of the report.
2. Color-coded Scores-at-a-Glance
3. Scores by Tool (OSSF Scorecard, Hipcheck, UP Custom Checks, Phylum.io)
4. Contributing Factors
5. OSS-P4/R Technical Metadata
6. Dependency Risk Factors

## Project Overview
Basic information about the project under analysis including the project name, repository, and project description
extracted from the project repository as well as the date the report was generated (current as of). Links to the
detailed sections at the end of the report are also included.

![OSS-P4/R Report Overview](/docs/assets/oss-p4r%20report%20overview.png)

## Scores at a Glance
The project's scores are broken down and aligned in two ways.

1. Project, Product, Protection, Policy (P4) Alignment
2. DoD CIO Software Supply Chain Security Alignment

Each tool check is allocated to one (or more) categories within each alignment. Overall scores are provided 
for each category as well as broken down by tool within each alignment. These matricies allow for
teams and leadership to quickly focus in on areas of strength and weakness for the project as well
as identify the tools that generated each (sub-)score for later analysis.

![OSS-P4/R Scores at a Glance](/docs/assets/oss-pr4%20score%20overview.png)

Scores are color-coded according to the thresholds established.

## Scores by Tool (OSSF Scorecard, Hipcheck, UP Custom Checks, Phylum.io)
Following the DoD CIO Criteria alignment is the summary table of aggregate scores by each tool 
as well as a break-out of factors contributing to the score aligned to the DoD CIO criteria areas. 
Each factor is summaried as:

[ ![Error](/docs/assets/error.svg) / ![Warning](/docs/assets/warning.svg) ] _Check Name_ (_Check Score_ / _Check Threshold_ )

Icons indicate factors that fell below threshold or were unable to be determined, respectively. 
Factors above threshold present no icon. Factors that fall below threshold must be investigated and 
findings validated by the team. Valid findings should be prioritized for risk determination and mitigation.

Each factor score is a composite of individual checks performed by each tool. The checks performed are
reported in detail in the following section.

![OSS-P4/R Scores by Tool](/docs/assets/oss-p4r%20summary%20findings.png)

## Contributing Factors
Each composite sub-score is calculated based on various _checks_ performed by each tool. This section
breaks down the DoD CIO Criteria alignment areas and details out contributing factors, aligns 
tool checks performed to each factor, and presents whether a tool check flagged that factor. 
The same icons from the previous section are used here.

The report groups similar checks from different tools into a common lexicon of contributing factors
so that project owners can focus down on the specific areas of concern and identify the exact
causes for concern. Tools can be added to OSS-P4/R and mapped to this lexicon, as well as expand
the lexicon in future revisions of the tool.

![OSS-P4/R Example Security Checks Detail](/docs/assets/oss-p4r%20check%20details.png)

**Some checks are currently reported as _Manual_ and cannot be determined by OSS-P4/R at this time.** 
If the risk assessor requires an answer to _Manual_ checks then a human must obtain the information
and report the finding.

The following explains the purpose of each contributing factor.

### Security
| Contributing Factor           | Description                                                                                                                                                                         |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Trusted Sources               | Where the source code for the project resides and whether or not it is available (and used) from a trusted source.                                                                  |
| Public or Private             | Whether the project's repository is public or private.                                                                                                                              |
| Fully Unrestricted            | Whether the project's repository is fully unrestricted (allows reads and/or writes from any contributor).                                                                           |
| Login Credentials             | Whether the project uses secure access credentials and whether they are least privilege.                                                                                            |
| Use of Repository Protections | Whether the project's repository uses fine-grained protections to prevent unintended or malicious commits to critical branches.                                                     |
| Large Commits                 | Whether the project's repository has evidence of unusually large commits. Large commits can be used to smuggle in malicious code.                                                   |
| Obfuscated Code               | Whether or not the project exhibits evidence of obfuscated code in an attempt to circumvent SAST tooling.                                                                           |
| Binary Artifact(s)            | Whether or not the project contains binary artifacts as part of the project's source code. Binary artifacts can be used to smuggle malicious content circumventing detection tools. |
| Typosquatting                 | Whether or not the project uses a typosquatted dependency as opposed to the genuine one. Typosquatted dependencies can be a vector for attack.                                      |
| Engineering Risk              | Whether or not the project's source code or exhibits code or architectural quality issues.                                                                                          |
| Malicious Code                | Whether or not tools detected possible instances of malicious code in the project. These instances should be individually investigated.                                             |
| Known Vulnerabilities         | Number and severity of vulnerabilities reported on the project and its dependencies. The detail report follows at the end of the OSS-P4/R report.                                   |

### Integrity
| Contributing Factor                             | Description                                                                                                                               |
|-------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| Peer Reviews                                    | Whether or not (and to what extent) that the project exhibits evidence of peer review for changes (such as pull requests with comments).  |
| Use of Code and Security Scanners               | Whether or not (and to what extend) the project exhibits use of code and/or security scanners as part of its development process.         |
| Signed Commits                                  | Whether or not the project's commits are signed.                                                                                          |
| Cryptographically Signed Commits                | Whether or not the project's commits are cryptographically verifiable to a trusted source (i.e., certificate issued by a trusted issuer). |
| Cryptographically Signed Releases and Artifacts | Whether or not the project's releases and/or artifacts are cryptographically signed and verifiable.                                       |

### Dependencies
| Contributing Factor                         | Description                                                                                                                                                         |
|---------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Published Software Bill of Materials (SBOM) | Whether or not the project (or project's repository) publishes an SBOM.                                                                                             |
| Dependencies Pinned to Version              | Whether or not the project's dependencies are pinned to specific versions. This can be accomplished through the use of lock files in many languages and frameworks. |
| Dependencies up to Date                     | Whether or not the project's dependencies are up to date and whether or not a tool (i.e., Dependabot) is used to automate the process.                              |
| Number of OSS Dependencies                  | Total number open source of dependencies (direct and transitive).                                                                                                   |
| Number of Proprietary Dependencies          | Total number of propriety (non open source) dependencies (direct and transitive).                                                                                   |

### Malicious Actors
| Contributing Factor                       | Description                                                                                                           |
|-------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| Author(s) Known to Commit Vulnerabilities | Whether or not the project has among its contributors known author(s) who have committed vulnerable code in the past. |
| Author(s) Known to Commit Malicious Code  | Whether or not the project has among its contributors known author(s) who have committed malicious code in the past.  |

### Long Term Support
| Contributing Factor               | Description                                                                                                                                                                               |
|-----------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Project                           | The project's canonical repository and description (informational).                                                                                                                       |
| Individual or Organization        | Whether the project is maintained by an organization or individual and self-reported metadata about them (informational).                                                                 |
| Organization Type                 | Whether or not the type of organization could be determined (i.e., commercial company, non-profit foundation, university, research center, etc.).                                         |
| SLSA Level                        | Whether or not the project has attained a SLSA (Supply-chain Levels for Software Artifacts) level.                                                                                        |
| Best Practices                    | Checks whether or not the project uses CI and reports its status (i.e., uses Github badges to report on CI, tests, etc. passing).                                                         |
| Number of Abandoned Project(s)    | Whether or not the project and any of its dependencies are deemed to be abanded (i.e., not maintained).                                                                                   |
| OSSF Activity (criticality) Score | The OSSF Criticality Score of the project. This is a globally calculated value that measures the relative importance of this project to the open source community.                        |
| Commits                           | Reports the project's last commit date, days since first commit, and activity over the past 90 days. Activity on the project indicates maintenance. No activity may indicate abandonment. |
| Number of Contributors            | Total number of individual contributors to the project as well as diversity of those contributors (i.e., contributors from different organizations).                                      |
| Problem Reporting Process         | Whether or not the project accepts issue reports and number of current open issues.                                                                                                       |
| Vulnerability Reporting Process   | Whether or not the project's process for reporting security or vulnerability information could be determined.                                                                             |

### Suitability
| Contributing Factor | Description                                                                                                                                             |
|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| License             | The license(s) that the project is distributed under and whether one is compatible with use.                                                            |
| License Risk        | Looks at the licenses of the project's dependencies and reports whether there are possible conflicts with the license the project is distributed under. |

### Tool-specific Information
For more information on the checks run by each tool, please refer to their documentation:
- [OSSF Scorecard](https://github.com/ossf/scorecard/blob/main/docs/checks.md)
- [MITRE Hipcheck](https://github.com/mitre/hipcheck/blob/main/docs/book/src/using/analyses.md)
- [Phylum.io](https://docs.phylum.io/analytics)

## OSS-P4/R Technical Metadata
This section presents information that might be useful for debugging or troubleshooting and
includes information such as the run date, OSS-P4/R version used to generate the report, 
Metadata for Phylum run(s), time ellapsed to complete, the invocation command line, and
summary comments/caveats that impact thresholds and reproducability of the report.

## Dependency Risk Factors
The last section, and likely most lengthy, is the dependency risk factor details. This section
reports upon:

1. Critical and High Vulnerabilities in the project or its dependencies
2. Critical and High potential instances of malicious code risk in the project or its dependencies
3. Critical and High potential instances of engineering risk in the project
4. Critical and High potential instances of author risk
5. All instances of potential license risk

### Vulnerabilities
While OSS-P4/R provides a detailed report on **known** vulnerabilities in the project and its dependencies
it is not intended to replace a more rigorous vulnerability management process. Rather, this report
is intended to highlight the totality of the vulnerability landscape for the project and its dependencies.
If a project has known vulnerabilities, those certainly need to be prioritized and addressed as they
are able to be directly explointed. Vulnerabilities in dependencies is harder to determine whether or not
they impact the project. OSS-P4/R does not attempt to make that determination. Using dependencies with
vulnerabilities (particularly of critical and high severity) exposes the project to increasing levels of risk
as the number and severity of those vulnerabilities increases. A project team can attempt to mitigate the 
impacts of those vulnerabilities, however the risk that those mitigations prove to be ineffective increases 
as the number of mitigations increases. It is better for teams to avoid using dependencies with known 
vulnerabilities and they are encouraged to update dependencies to newer versions on a regular basis.

![OSS-P4/R Example Vulnerability Finding](/docs/assets/oss-p4r%20example%20cve.png)

### Malicious Code Risk
The malicious code risk section details out findings that _may_ be actually malicious or could be used
for malicious purposes if implemented improperty or not protected appropriately. Each finding should
be reviewed for applicability to the project.

![OSS-P4/R Example Typosquatting Finding](/docs/assets/oss-p4r%20example%20typosquat.png)

### Engineering Risk
The engineering risk section details out findings of instances that _may_ indicate poor engineering
practices. These instances are particular to the project and should be investigated. Findings include
such issues like empty files, commented out code, unreachable code, etc. The team should investigate
each finding and determine the correct remediation.

### Author Risk
The author risk section details out each finding of a suspicious author contributing to the project
code base or of one of its dependencies.

### License Risk
The license risk section details out each instance of potential license incompatibility between the 
project and its dependencies. Not all findings are impactful, rather they _could_ be impactful 
depending on how the project uses the dependency. Each finding should be reviewed to determine
whether or not it impacts the project.

![OSS-P4/R Example License Finding](/docs/assets/oss-p4r%20example%20license%20finding.png)
