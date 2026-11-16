# Build from the repo root (the rules live in the mod's relay.lua):
#   docker build -f server/Dockerfile .
FROM node:22-alpine
WORKDIR /app
COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev
COPY server/src ./server/src
COPY mod/BalatroMultiplayer/src/relay.lua mod/BalatroMultiplayer/src/json.lua ./mod/BalatroMultiplayer/src/
ENV PORT=8788
EXPOSE 8788
USER node
CMD ["node", "server/src/server.js"]
