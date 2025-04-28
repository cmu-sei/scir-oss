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
    && apt-get install --no-install-recommends -y ca-certificates procps bc jq unzip file

USER hc_user
ENV HOME /home/hc_user 

RUN set -eux \
    && curl --proto '=https' --tlsv1.2 -LsSf https://github.com/mitre/hipcheck/releases/download/hipcheck-v${HC_VERSION}/hipcheck-installer.sh | sh \
    && $HOME/.local/bin/hc setup

#
# the phylum script has a openssl verification step
# to confirm the digital signature for said script
#
RUN curl https://sh.phylum.io/ | sh -s -- --yes

#
# the grype script uses cosign to verify the script
# TODO: install and get this to pass a cosign/sigstore verification
#
#RUN curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -v -b /home/hc_user/.local/bin
RUN curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /home/hc_user/.local/bin

COPY --from=gcr.io/openssf/scorecard:latest /scorecard /home/hc_user/.local/bin/
ADD local-assets/docker/bin/criticality_score-unknown-se50df0e9_linux_amd64 $HOME/.local/bin/criticality_score
COPY --from=hipcheck:2022-07-06-delivery /app/hc /home/hc_user/.local/bin/hc-v3.1.0
COPY --from=mitre/hipcheck:3.3.1 /app/hc /home/hc_user/.local/bin/hc-v3.3.1
#ADD local-assets/docker/bin/hc-v3.3.1_linux_amd64 $HOME/.local/bin/

RUN set -eux \
    && mkdir -p $HOME/.local/bin/settings

ADD scir-oss.sh $HOME/.local/bin/
ADD pub-scir.sh $HOME/.local/bin/
ADD settings/ $HOME/.local/bin/settings/

USER root
RUN chown hc_user:hc_user $HOME/.local/bin/settings/scir-oss/localizations.lib.sh

USER hc_user
RUN echo "# added by docker build" >> $HOME/.local/bin/settings/scir-oss/localizations.lib.sh \
    && echo "_LOCAL_OSSFCS=/home/hc_user/.local/bin/criticality_score" >> $HOME/.local/bin/settings/scir-oss/localizations.lib.sh \
    && echo "_LOCAL_OSSFSC=/home/hc_user/.local/bin/scorecard" >> $HOME/.local/bin/settings/scir-oss/localizations.lib.sh \
    && echo "_LOCAL_MITRHC=/home/hc_user/.local/bin/hc-v3.3.1" >> $HOME/.local/bin/settings/scir-oss/localizations.lib.sh

ENV SCIR_CONTAINER=true
ENV PATH=${HOME}/.local/bin:${PATH}

ENV HC_CONFIG="/home/hc_user/.config/hipcheck"
#ENTRYPOINT ["/home/hc_user/.local/bin/hc"]
#CMD ["help"]
ENTRYPOINT ["/home/hc_user/.local/bin/scir-oss.sh"]
CMD ["-h"]
