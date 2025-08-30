# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Collection of bash scripts for automating maintenance tasks on remote RunPod instances running ComfyUI. Scripts use RunPod's S3 API for file synchronization and management.

## Commands

### Setup
```bash
# Copy and configure credentials
cp config/runpod.conf.example config/runpod.conf
# Edit config/runpod.conf with your RunPod S3 credentials
```

### Workflow Sync
```bash
# Sync workflows from RunPod to local
./scripts/sync-workflows.sh

# Dry run to see what would be synced
./scripts/sync-workflows.sh --dry-run

# Verbose output
./scripts/sync-workflows.sh --verbose
```

## Architecture

### Directory Structure
- `scripts/` - Executable bash scripts for RunPod maintenance
- `config/` - Configuration files (credentials stored here)
- `workflows/` - Local copy of synced ComfyUI workflows

### Configuration System
All scripts source `config/runpod.conf` for:
- RunPod S3 API credentials
- Remote path mappings
- Regional settings

Scripts validate required environment variables and provide helpful error messages for missing configuration.

### Error Handling
- All scripts use `set -euo pipefail` for strict error handling
- Dependencies are checked before execution
- AWS CLI configuration is handled programmatically

## Dependencies

- AWS CLI (installed via `brew install awscli` on macOS)
- RunPod S3 credentials configured in `config/runpod.conf`