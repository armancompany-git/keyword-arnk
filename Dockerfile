# -------------------------------
# 1) Install deps
# -------------------------------
FROM node:22.11.0-alpine3.20 AS deps
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --legacy-peer-deps

COPY . .


# -------------------------------
# 2) Build Next.js
# -------------------------------
FROM node:22.11.0-alpine3.20 AS builder
WORKDIR /app

COPY --from=deps /app ./

# Cleanup unnecessary dev folders
RUN rm -rf /app/data /app/__tests__ /app/__mocks__

# Build Next.js standalone output
RUN npm run build


# -------------------------------
# 3) Final production runtime
# -------------------------------
FROM node:22.11.0-alpine3.20 AS runner
WORKDIR /app

ENV NODE_ENV=production

# Create non-root user
RUN addgroup -S nodejs && adduser -S nextjs -G nodejs

# Create persistent folder (for your DB)
RUN mkdir -p /app/data && chown nextjs:nodejs /app/data

# Copy Next.js production build
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# Copy cron + backend files
COPY --from=builder --chown=nextjs:nodejs /app/cron.js ./
COPY --from=builder --chown=nextjs:nodejs /app/email ./email
COPY --from=builder --chown=nextjs:nodejs /app/database ./database
COPY --from=builder --chown=nextjs:nodejs /app/.sequelizerc ./.sequelizerc

# Copy entrypoint and give executable rights
COPY --from=builder /app/entrypoint.sh /app/entrypoint.sh
RUN chown nextjs:nodejs /app/entrypoint.sh && chmod 755 /app/entrypoint.sh

# Install only required runtime deps
RUN npm install -g concurrently && \
    npm install cryptr@6.0.3 dotenv@16.0.3 croner@9.0.0 \
    @googleapis/searchconsole@1.0.5 sequelize-cli@6.6.2 \
    @isaacs/ttlcache@1.4.1

USER nextjs

EXPOSE 3000

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["concurrently", "node server.js", "node cron.js"]
