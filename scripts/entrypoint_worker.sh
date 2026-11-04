#!/bin/bash
# entrypoint_worker.sh — entrypoint for the heddle_worker release

set -e

echo "Waiting for database..."
while ! /app/bin/heddle_worker eval "HeddleCore.Repo.__adapter__().storage_status(HeddleCore.Repo.config())" > /dev/null 2>&1; do
  echo "Database not ready, retrying in 2s..."
  sleep 2
done

echo "Database ready!"

echo "Starting worker application..."
exec /app/bin/heddle_worker start
