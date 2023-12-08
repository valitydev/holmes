ARG OTP_VERSION

FROM docker.io/library/erlang:${OTP_VERSION} AS builder

COPY . /holmes
WORKDIR /holmes
RUN make
RUN ./clone-proto-modules.sh /repos

FROM docker.io/library/erlang:${OTP_VERSION}

RUN curl -fSsL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor |  tee /usr/share/keyrings/postgresql.gpg > /dev/null \
    && echo deb [arch=amd64,arm64,ppc64el signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main | tee /etc/apt/sources.list.d/postgresql.list \
    && apt-get --yes update \
    && apt-get --yes --no-install-recommends install \
        curl \
        bind9-dnsutils \
        git \
        iproute2 \
        iputils-ping \
        iputils-tracepath \
        less \
        nano \
        netcat-openbsd \
        jq \
        python3-pip \
        postgresql-client-15 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && pip install six

# step-cli
ARG STEP_VERSION
ARG TARGETARCH
RUN wget -nv -O step-cli.deb "https://dl.step.sm/gh-release/cli/gh-release-header/v${STEP_VERSION}/step-cli_${STEP_VERSION}_${TARGETARCH}.deb" \
    && dpkg -i step-cli.deb \
    && rm -vf step-cli.deb

# thrift
ARG THRIFT_VERSION
ARG TARGETARCH
RUN wget -nv -O- "https://github.com/valitydev/thrift/releases/download/${THRIFT_VERSION}/thrift-${THRIFT_VERSION}-linux-${TARGETARCH}.tar.gz" \
    | tar -xvz -C /usr/local/bin/

# woorl
ARG WOORL_VERSION
RUN wget -nv -O- "https://github.com/valitydev/woorl/releases/download/${WOORL_VERSION}/woorl-${WOORL_VERSION}.tar.gz" \
    | tar -xvz -C /usr/local/bin/ \
    && ln -sf woorl /usr/local/bin/woorl-json

COPY ./scripts /opt/holmes/scripts
COPY --from=builder /repos /opt/holmes/
COPY --from=builder /holmes/lib/scripts /opt/holmes/scripts
COPY woorlrc.sample /opt/holmes/

WORKDIR /opt/holmes
ENV CHARSET=UTF-8
ENV LANG=C.UTF-8
CMD ["/usr/local/bin/epmd"]
