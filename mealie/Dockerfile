# Wrap the official Mealie image, pinned
ARG BUILD_FROM=ghcr.io/mealie-recipes/mealie:v3.1.2
FROM ${BUILD_FROM}

USER root

# Install jq + tzdata (try apk, then apt, then microdnf)
RUN set -eux; \
    (apk add --no-cache jq tzdata curl || \
     (apt-get update && apt-get install -y --no-install-recommends jq tzdata curl && rm -rf /var/lib/apt/lists/*) || \
     (microdnf install -y jq tzdata curl && microdnf clean all)) || true

COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

EXPOSE 9000

# Keep upstream ENTRYPOINT if present; run our wrapper as CMD
CMD ["/usr/local/bin/run.sh"]
