# Nakama with the bundled TypeScript runtime and the production config. Build after `npm run build`
# (build/index.js carries the data/*.json content hash, so build it from the same data as the worker and APK).
FROM registry.heroiclabs.com/heroiclabs/nakama:3.41.0

COPY build/index.js /nakama/data/modules/index.js
COPY prod.yml /nakama/data/prod.yml
