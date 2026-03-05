#!/usr/bin/env bash

set -e

echo "Starting Drive Sync workflow"

gh workflow run drive-sync.yml --ref main

sleep 5

RUN_ID=$(gh run list --workflow=drive-sync.yml -L 1 --json databaseId -q '.[0].databaseId')

echo "Watching run $RUN_ID"

gh run watch "$RUN_ID" --exit-status

echo "Drive Sync finished"
