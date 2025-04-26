# SPDX-License-Identifier: Apache-2.0

FROM node:bookworm-slim

ARG HC_VERSION="3.13.0"

WORKDIR /app

RUN set -eux \
    && apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates git curl xz-utils mold \
    && rm -rf /var/lib/apt/lists/* \
    && adduser --disabled-password hc_user \
    && chown -R hc_user /app \
    && apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates procps bc jq

USER hc_user
ENV HOME /home/hc_user 

RUN set -eux \
    && curl --proto '=https' --tlsv1.2 -LsSf https://github.com/mitre/hipcheck/releases/download/hipcheck-v${HC_VERSION}/hipcheck-installer.sh | sh \
    && $HOME/.local/bin/hc setup

COPY --from=gcr.io/openssf/scorecard:latest /scorecard /home/hc_user/.local/bin/
ADD local-assets/docker/bin/criticality_score-unknown-se50df0e9_linux_amd64 $HOME/.local/bin/criticality_score
ADD local-assets/docker/bin/hc-v3.3.1_linux_amd64 $HOME/.local/bin/

RUN set -eux \
    && mkdir -p $HOME/.local/bin/settings

ADD scir-oss.sh $HOME/.local/bin/
ADD pub-scir.sh $HOME/.local/bin/
ADD settings/ $HOME/.local/bin/settings/

ENV SCIR_CONTAINER=true

ENV HC_CONFIG="/home/hc_user/.config/hipcheck"
#ENTRYPOINT ["/home/hc_user/.local/bin/hc"]
#CMD ["help"]
ENTRYPOINT ["/home/hc_user/.local/bin/scir-oss.sh"]
CMD ["-h"]
