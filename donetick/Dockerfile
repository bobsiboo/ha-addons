ARG BUILD_FROM
FROM ${BUILD_FROM}

# Upstream Donetick image is Alpine-based; install tools we need
RUN apk add --no-cache bash jq

# Our tiny entrypoint: creates /config/selfhosted.yaml from HA options
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use our entrypoint, then run upstream's default CMD ("donetick")
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# remove CMD ["donetick"]
