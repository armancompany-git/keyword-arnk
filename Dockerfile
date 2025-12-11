# Stage 1: Dependency Installation (deps)
# Installs all necessary packages including dev dependencies
FROM node:22.11.0-alpine3.20 AS deps
ENV NPM_VERSION=10.3.0
RUN npm install -g npm@"${NPM_VERSION}"
WORKDIR /app

COPY package.json ./
RUN npm install
COPY . .


# Stage 2: Application Build (builder)
# Creates the optimized build artifacts (.next)
FROM node:22.11.0-alpine3.20 AS builder
WORKDIR /app
ENV NPM_VERSION=10.3.0
RUN npm install -g npm@"${NPM_VERSION}"
# Copy all installed dependencies and source code
COPY --from=deps /app ./
# Remove unnecessary development/test files
RUN rm -rf /app/data /app/__tests__ /app/__mocks__
# Run the build process
RUN npm run build


# Stage 3: Production Runner (runner)
# Minimal image for serving the application
FROM node:22.11.0-alpine3.20 AS runner
WORKDIR /app
ENV NPM_VERSION=10.3.0
RUN npm install -g npm@"${NPM_VERSION}"

# Environment Setup
ENV NODE_ENV=production

# 1. User Setup for Security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
# Create and set ownership for any runtime directories (like /app/data)
RUN set -xe && mkdir -p /app/data && chown nextjs:nodejs /app/data

# 2. Copy Build Artifacts
# Use --chown to ensure correct file ownership from the start
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 3. Copy Runtime Files (Cron, Email, Database configs, Entrypoint)
COPY --from=builder --chown=nextjs:nodejs /app/cron.js ./
COPY --from=builder --chown=nextjs:nodejs /app/email ./email
COPY --from=builder --chown=nextjs:nodejs /app/database ./database
COPY --from=builder --chown=nextjs:nodejs /app/.sequelizerc ./.sequelizerc
COPY --from=builder --chown=nextjs:nodejs /app/entrypoint.sh ./entrypoint.sh

# 4. CRITICAL FIX: Ensure entrypoint script is executable
# This prevents the "Permission denied" error
RUN chmod +x /app/entrypoint.sh

# 5. Install Production Runtime Dependencies
# Remove original package.json (already installed/built)
RUN rm package.json
# Initialize new package.json for the runtime-only dependencies
RUN npm init -y
# Install required runtime dependencies and global tools (concurrently)
RUN npm i cryptr@6.0.3 dotenv@16.0.3 croner@9.0.0 @googleapis/searchconsole@1.0.5 sequelize-cli@6.6.2 @isaacs/ttlcache@1.4.1 \
    # Clean up NPM cache after local installs to keep the image small
    && npm cache clean --force
RUN npm i -g concurrently \
    # Clean up NPM cache after global installs
    && npm cache clean --force

# 6. Run as the non-root user
USER nextjs

# 7. Configure Container Startup
EXPOSE 3000
ENTRYPOINT ["/app/entrypoint.sh"]
# Use Exec form for CMD, which relies on the ENTRYPOINT script
CMD ["concurrently", "node", "server.js", "node", "cron.js"]
