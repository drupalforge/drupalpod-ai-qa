#!/usr/bin/env bash

#Update sudo (might be overkill).
time sudo apt-get update

# Prepare so it works in devpanel also.
sudo apt -y install curl ca-certificates apt-transport-https
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
. /etc/os-release
sudo sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"
sudo apt-get update

#== Install postgresql on the host.
echo 'PostgreSQL is not installed. Installing it now.'
# Install PostgreSQL 17 and pgvector extension
time sudo apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-pgvector
# Verify installation
if ! dpkg -l | grep -q postgresql-17-pgvector; then
  echo "ERROR: postgresql-17-pgvector package not installed!"
  exit 1
fi
echo "PostgreSQL 17 and pgvector extension installed successfully"
#== Make it less promiscuous in DDEV only.
if env | grep -q DDEV_PROJECT; then
  sudo chmod 0755 /usr/bin
  sudo chmod 0755 /usr/sbin
  #== Start the PostgreSQL service.
  env PATH="/usr/sbin:/usr/bin:/sbin:/bin" sudo service postgresql start
else
  #== In Devpanel/GitHub Actions - install fresh
  echo "Starting PostgreSQL service..."
  sudo service postgresql start

  # Wait for PostgreSQL to be ready
  for i in {1..30}; do
    if sudo su postgres -c "psql -c 'SELECT 1'" &>/dev/null; then
      echo "PostgreSQL is ready"
      break
    fi
    echo "Waiting for PostgreSQL to start... ($i/30)"
    sleep 1
  done

  echo "Creating database user 'db'..."
  sudo su postgres -c "psql -c \"CREATE ROLE db WITH LOGIN PASSWORD 'db';\"" || echo "User might already exist"

  echo "Creating database 'db'..."
  sudo su postgres -c "psql -c \"CREATE DATABASE db WITH OWNER db ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0;\"" || echo "Database might already exist"

  echo "Enabling pgvector extension..."
  if sudo su postgres -c "psql -d db -c \"CREATE EXTENSION IF NOT EXISTS vector;\""; then
    echo "✓ pgvector extension enabled successfully"
  else
    echo "✗ Failed to enable pgvector extension"
    exit 1
  fi
fi

# Make sure that php has pgsql installed.
sudo apt install -y libpq-dev
sudo -E docker-php-ext-install pgsql
