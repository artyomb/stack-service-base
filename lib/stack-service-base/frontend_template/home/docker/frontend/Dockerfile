FROM node:24.18-alpine AS base

RUN apk upgrade --no-cache \
    && npm install --global npm@12.0.2 --no-audit --no-fund --no-update-notifier \
    && npm pkg delete devDependencies --prefix "$(npm root --global)/npm" \
    && npm update --prefix "$(npm root --global)/npm" --omit=dev --ignore-scripts --no-audit --no-fund --no-update-notifier \
    && npm cache clean --force

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

FROM base AS tests
CMD ["npm", "run", "check"]

FROM base AS build

RUN npm run build

FROM nginxinc/nginx-unprivileged:1.30.4-alpine AS deploy

USER root
RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates curl jq \
    && rm -rf /usr/share/nginx/html/*

ENV PORT=8080 \
    NODE_ENV=production \
    PATH_PREFIX= \
    API_BASE_URL= \
    LOG_LEVEL=info \
    BACKEND_URL=http://127.0.0.1:65535

COPY --from=docker /frontend/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --chmod=755 --from=docker /frontend/15-runtime-settings.envsh /docker-entrypoint.d/
COPY --chmod=755 --from=docker /frontend/40-path-prefix-settings.sh /docker-entrypoint.d/
COPY --chmod=755 --from=docker /frontend/45-runtime-config-settings.sh /docker-entrypoint.d/
RUN rm -f /etc/nginx/conf.d/default.conf \
    && chown -R 101:101 /etc/nginx/conf.d /usr/share/nginx/html

COPY --chown=101:101 --from=build /app/dist /usr/share/nginx/html

USER 101:101

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD curl -fsS "http://127.0.0.1:${PORT}/healthcheck" || exit 1

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
