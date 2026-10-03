# Headless Godot validation worker (tools/worker/worker.gd). Build from the repo root:
#   docker build -f tools/worker/Dockerfile -t bio-siege-worker .
# The image carries data/*.json, so build it from the same data as the server bundle and the APK.
FROM debian:12-slim

ARG GODOT_VERSION=4.7.2
# From https://github.com/godotengine/godot/releases/download/4.7.2-stable/SHA512-SUMS.txt
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& curl -fsSL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm -rf /tmp/godot /tmp/godot.zip \
	&& apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 worker && install -d -o worker -g worker /app
WORKDIR /app
COPY --chown=worker:worker . /app
USER worker

# Build the class cache at image build time so start-up is quick and class_name scripts resolve.
# The second command fails the build if the class cache or data/*.json is broken.
RUN godot --headless --path /app --import >/dev/null 2>&1; \
	godot --headless --path /app -s tools/print_content_hash.gd

ENTRYPOINT ["/bin/sh", "-c", "exec godot --headless --path /app -s tools/worker/worker.gd -- --url=\"$BIO_SIEGE_SERVER_URL\" --http-key=\"$BIO_SIEGE_HTTP_KEY\" \"$@\"", "worker"]
