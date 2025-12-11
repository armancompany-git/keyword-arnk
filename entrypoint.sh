#!/bin/sh
# Exit immediately if a command exits with a non-zero status.
set -e

# CRITICAL FIX: Change to the application's working directory.
# This ensures that 'concurrently' and 'node' can find server.js and cron.js.
cd /app

echo "Running database migrations..."
# Execute the migration command
npx sequelize-cli db:migrate --env production

echo "Starting application processes with concurrently..."
# Use 'exec' to replace the shell process with the main application process.
# This ensures proper signal handling (SIGTERM) is passed to 'concurrently'.
exec concurrently "node server.js" "node cron.js"
