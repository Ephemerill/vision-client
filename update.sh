#!/bin/bash

# This script updates the project from its Git remote.
# Assumes the "remote" is "origin" and the branch is "main".

echo "Pulling latest changes from GitHub..."

# Get the directory this script is in
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

cd "${SCRIPT_DIR}" || { echo "Failed to change directory."; exit 1; }

# Fetch changes
git fetch origin

# Check for differences
UPSTREAM_HASH=$(git rev-parse origin/main)
LOCAL_HASH=$(git rev-parse @)

if [ "${LOCAL_HASH}" == "${UPSTREAM_HASH}" ]; then
    echo "Already up to date."
else
    echo "Updating..."
    git pull origin main
    if [ $? -eq 0 ]; then
        echo "Update successful."
        # Re-apply execute permissions just in case
        chmod +x *.sh
    else
        echo "Update failed. Please check for local conflicts."
    fi
fi