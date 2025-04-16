# OSS-P4/R &#x2621;

_"Be Aware" of the Project, Product, Protections, and Policy of OSS Components._

The ability to freely inspect the source code of a software product is an
important part of determining supply chain risk. But just as important is
the ability to inspect the practices and policies a project employs to
protect the integrity of that source code.

## Overview

OSS-P4/R uses public data sources and Open Source tools to gather data and
information correlated to supply chain concerns which consider various aspects
of the project and those project's dependencies.

![Example](./docs/examples/oparest_example.svg)

```sh
# Obtain supply chain inforrmation about a Open Source project given
# its GitHub name and repository and any Software Bill of Materials
# represented by the project and its dependencies.
scir-oss.sh -C oparest -G go-training/opa-restful -P github:sbom 

# Perform the same analysis with a Software Bill of Materials generated
# in SPDX from a locally scanned folder
scir-oss.sh -C oparest -G go-training/opa-restful -P myOpaRest.spdx.json:sbom 

# After analysis, published the results to an Atlassian Confluence site
pub-scir.sh -C oparest -T "OPA REST-API" -S MySpace -A "OSS-P4/R Reports"

# Or, view the results using a local Markdown viewer
glow oparest/oparest_scir.md
```

[Click here to see the complete OPA REST-API report in Markdown](./docs/examples/oparest_scir.md)

[![homepage][1]][2]

For more information, check out the [Quickstart Guide][quickstart].

## Installation

See the [Installation Instructions][install].

## License

OSS-P4/R is licensed under an MIT-style license, which can be
found in the [`LICENSE`](license.txt) file in this repository.

## Public Release

> Open Source P4 Tool
> 
> Copyright 2024 Carnegie Mellon University.
> 
> NO WARRANTY. THIS CARNEGIE MELLON UNIVERSITY AND SOFTWARE ENGINEERING INSTITUTE MATERIAL IS FURNISHED ON AN "AS-IS" BASIS. CARNEGIE MELLON UNIVERSITY MAKES NO WARRANTIES OF ANY KIND, EITHER EXPRESSED OR IMPLIED, AS TO ANY MATTER INCLUDING, BUT NOT LIMITED TO, WARRANTY OF FITNESS FOR PURPOSE OR MERCHANTABILITY, EXCLUSIVITY, OR RESULTS OBTAINED FROM USE OF THE MATERIAL. CARNEGIE MELLON UNIVERSITY DOES NOT MAKE ANY WARRANTY OF ANY KIND WITH RESPECT TO FREEDOM FROM PATENT, TRADEMARK, OR COPYRIGHT INFRINGEMENT.
> 
> Licensed under a MIT-style license, please see license.txt or contact permission@sei.cmu.edu for full terms.
> 
> [DISTRIBUTION STATEMENT A] This material has been approved for public release and unlimited distribution.  > Please see Copyright notice for non-US Government use and distribution.
> 
> This Software includes and/or makes use of Third-Party Software each subject to its own license.
> 
> DM24-0786
> 
> Applies to ```pubRel 240719a (branch: publicRelease)``` versions or later.

[quickstart]: ./docs/manuals/README-running.md
[install]: ./docs/manuals/README-install.md
[license]: https://github.com/cmu-sei/scir-oss/blob/main/license.txt
[release]: https://github.com/cmu-sei/scir-oss
[rfd_2]: https://hipcheck.mitre.org/docs/rfds/0002/
[website]: https://sei.cmu.edu
[1]: ./docs/assets/MD_icon.png
[2]: ./docs/examples/oparest_scir.md
