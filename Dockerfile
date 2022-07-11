ARG OTP_VERSION

FROM docker.io/library/erlang:${OTP_VERSION} AS builder

COPY . /holmes
WORKDIR /holmes
RUN make
RUN ./clone-proto-modules.sh /repos

FROM docker.io/library/erlang:${OTP_VERSION}

RUN apt-get --yes update \
    && apt-get --yes --no-install-recommends install \
        curl=7.74.0-1.3+deb11u1 \
        bind9-dnsutils=1:9.16.27-1~deb11u1 \
        git=1:2.30.2-1 \
        iproute2=5.10.0-4 \
        iputils-ping=3:20210202-1 \
        iputils-tracepath=3:20210202-1 \
        less=551-2 \
        nano=5.4-2+deb11u1 \
        netcat-openbsd=1.217-3 \
        jq=1.6-2.1 \
        postgresql-client-13=13.7-0+deb11u1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# step-cli
ARG STEP_VERSION
ARG TARGETARCH
RUN wget -nv -O step-cli.deb "https://dl.step.sm/gh-release/cli/docs-cli-install/v${STEP_VERSION}/step-cli_${STEP_VERSION}_${TARGETARCH}.deb" \
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
