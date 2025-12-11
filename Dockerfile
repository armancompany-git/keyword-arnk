# Stage 1: Dependency Installation (deps)
FROM node:22.11.0-alpine3.20 AS deps
ENV NPM_VERSION=10.3.0
RUN npm install -g npm@"${NPM_VERSION}"
WORKDIR /app

COPY package.json ./
RUN npm install
COPY . .


# Stage 2: Application Build (builder)
FROM node:22.11.0-alpine3.20 AS builder
WORKDIR /app
ENV NPM_VERSION=10.3.0
RUN npm install -g npm@"${NPM_VERSION}"
COPY --from=deps /app ./
# Cleanup dev files
RUN rm -rf /app/data /app/__tests__ /app/__mocks__
RUN npm run build


# Stage 3: Production Runner (runner)
FROM node:22.11.0-alpine3.20 AS runner
WORKDIR /app
ENV NPM_VERSION=10.3.0
RUN npm install -g npm@"${NPM_VERSION}"
ENV NODE_ENV=production

# 1. User Setup
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
RUN set -xe && mkdir -p /app/data && chown nextjs:nodejs /app/data

# 2. Copy Files and Artifacts
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/cron.js ./
COPY --from=builder --chown=nextjs:nodejs /app/email ./email
COPY --from=builder --chown=nextjs:nodejs /app/database ./database
COPY --from=builder --chown=nextjs:nodejs /app/.sequelizerc ./.sequelizerc
COPY --from=builder --chown=nextjs:nodejs /app/entrypoint.sh ./entrypoint.sh

# 3. Permissions and Dependencies
# CRITICAL FIX 1: Ensure entrypoint script is executable
RUN chmod +x /app/entrypoint.sh
RUN rm package.json
RUN npm init -y
RUN npm i cryptr@6.0.3 dotenv@16.0.3 croner@9.0.0 @googleapis/searchconsole@1.0.5 sequelize-cli@6.6.2 @isaacs/ttlcache@1.4.1 \
    && npm cache clean --force
RUN npm i -g concurrently \
    && npm cache clean --force

# 4. Final Configuration
USER nextjs

EXPOSE 3000
ENTRYPOINT ["/app/entrypoint.sh"]
# CRITICAL FIX 2: CMD is empty so the ENTRYPOINT runs its own fixed logic.
CMD []
