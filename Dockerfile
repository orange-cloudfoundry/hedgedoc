FROM --platform=$BUILDPLATFORM docker.io/library/node:20.7.0-bullseye-slim@sha256:86ed0f70880231adc0fb66c2edbba5de350d8587999e2fe4e1f59c11a4cbb3b4 AS builder

# Build arguments to change source url, branch or tag
ARG CODIMD_REPOSITORY
ARG HEDGEDOC_REPOSITORY=https://github.com/orange-cloudfoundry/hedgedoc.git
ARG VERSION=master
#necessary on ARM because puppeteer doesn't provide a prebuilt binary
ENV PUPPETEER_SKIP_DOWNLOAD=true

# Clone the source and remove git repository but keep the HEAD file
RUN --mount=target=/var/lib/apt/lists,type=cache,sharing=locked \
    --mount=target=/var/cache/apt,type=cache,sharing=locked \
    apt-get update && \
    apt-get install --no-install-recommends -y git jq ca-certificates python-is-python3 build-essential
#RUN git clone --depth 1 --branch "$VERSION" "$HEDGEDOC_REPOSITORY" /hedgedoc
#RUN git -C /hedgedoc log --pretty=format:'%ad %h %d' --abbrev-commit --date=short -1
#RUN git -C /hedgedoc rev-parse HEAD > /tmp/gitref
COPY . /hedgedoc
RUN rm -rf /hedgedoc/.git/*
#RUN mv /tmp/gitref /hedgedoc/.git/HEAD
RUN jq ".repository.url = \"${HEDGEDOC_REPOSITORY}\"" /hedgedoc/package.json > /hedgedoc/package.new.json
RUN mv /hedgedoc/package.new.json /hedgedoc/package.json

# Install app dependencies and build
WORKDIR /hedgedoc

RUN yarn install
RUN yarn run build

FROM docker.io/library/node:20.7.0-bullseye-slim@sha256:86ed0f70880231adc0fb66c2edbba5de350d8587999e2fe4e1f59c11a4cbb3b4 AS modules-installer
WORKDIR /hedgedoc

ENV NODE_ENV=production

COPY --from=builder /hedgedoc /hedgedoc

RUN --mount=target=/var/lib/apt/lists,type=cache,sharing=locked \
    --mount=target=/var/cache/apt,type=cache,sharing=locked \
    apt-get update && \
    apt-get install --no-install-recommends -y git ca-certificates python-is-python3 build-essential

#RUN yarn workspaces focus --production
# We get the following error problem, because the dependacie is only in dev dependancies in the package.json
#Error: Cannot find module 'babel-runtime/core-js/json/stringify'



FROM docker.io/library/node:20.7.0-bullseye-slim@sha256:86ed0f70880231adc0fb66c2edbba5de350d8587999e2fe4e1f59c11a4cbb3b4 AS app

LABEL org.opencontainers.image.title='HedgeDoc production image(debian)'
LABEL org.opencontainers.image.url='https://hedgedoc.org'
LABEL org.opencontainers.image.source='https://github.com/hedgedoc/container'
LABEL org.opencontainers.image.documentation='https://github.com/hedgedoc/container/blob/master/README.md'
LABEL org.opencontainers.image.licenses='AGPL-3.0'
LABEL org.opencontainers.image.name="hedgedoc-Orange"

WORKDIR /hedgedoc

ARG UID=10000
ENV NODE_ENV=production
ENV UPLOADS_MODE=0700

RUN apt-get update && \
    apt-get install --no-install-recommends -y gosu && \
    rm -r /var/lib/apt/lists/*

# Create hedgedoc user
RUN adduser --uid $UID --home /hedgedoc/ --disabled-password --system hedgedoc

COPY --chown=$UID --from=modules-installer /hedgedoc /hedgedoc

# Add configuraton files
COPY ["resources/config.json", "/files/"]

# Healthcheck
COPY --chown=$UID /resources/healthcheck.mjs /hedgedoc/healthcheck.mjs
HEALTHCHECK --interval=15s CMD node healthcheck.mjs

# For backwards compatibility
RUN ln -s /hedgedoc /codimd

# Symlink configuration files
RUN rm -f /hedgedoc/config.json
RUN ln -s /files/config.json /hedgedoc/config.json

EXPOSE 3000

COPY ["resources/docker-entrypoint.sh", "/usr/local/bin/docker-entrypoint.sh"]
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["node", "app.js"]
