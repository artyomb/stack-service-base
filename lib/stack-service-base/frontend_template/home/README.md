# ${service_name}

Framework-neutral frontend service starter for the corporate stack. It includes
local development, checks, production build, nginx runtime, containers, and CI.
Choose the UI framework, router, and domain structure, and adapt the supplied
infrastructure to the service requirements.

## Development

Node.js 24.21.0 LTS is required for local development.

    cd src
    cp .env.example .env.local
    npm ci
    npm start

The development server listens on http://localhost:3000. Set BACKEND_URL in
.env.local to enable the same-origin /api proxy.

Application code and tests may use JavaScript, TypeScript, or both. TypeScript
remains strict; JavaScript requires no type annotations and is checked by ESLint.

## Checks

    cd src
    npm test
    npm run check

`npm test` runs the tests. `npm run check` additionally runs TypeScript
validation, ESLint, and a production build.

Run a local production preview with:

    npm run preview

The preview command builds before serving. For a prefixed deployment, run
`PATH_PREFIX=/example npm run preview` and open
http://localhost:3000/example/.

## Container

    docker-compose -f docker/docker-compose.yml up --build

The service is available at http://localhost:7000. nginx runs unprivileged on
container port 8080, exposes /healthcheck, and supports PATH_PREFIX without
rebuilding the image.

PATH_PREFIX may be empty or contain letters, digits, `_`, `-`, and `/`.
The complete prefixes `/api`, `/assets`, and `/healthcheck` are reserved.

Browser-visible runtime configuration:

- PATH_PREFIX
- API_BASE_URL
- LOG_LEVEL

runtime-config.js is public; never put credentials or secrets into these values.
BACKEND_URL is server-only and configures the nginx /api proxy.

nginx uses a same-origin Content Security Policy. Extend the corresponding
directive in `docker/frontend/nginx.conf.template` when external resources are
required.

## CI

GitLab follows the same corporate `build-labels` orchestration as Ruby services.
Ruby only runs that tool; the frontend is tested and built with Node and served
by nginx at runtime.
