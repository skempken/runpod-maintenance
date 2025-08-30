# RunPod Maintenance Scripts

Collection of bash scripts for automating maintenance tasks on remote RunPod instances running ComfyUI. Scripts use SSH/rsync for reliable file synchronization and management.

## Features

- **Auto-detection** of running RunPod instances via `runpodctl`
- **SSH/rsync synchronization** for reliable file transfers
- **Automatic rsync installation** on Ubuntu-based pods
- **Comprehensive error handling** and validation
- **Safe defaults** (push doesn't delete by default)
- **Flexible usage** (supports manual IP/port specification)

## Quick Start

### Setup
```bash
# Copy and configure settings
cp config/runpod.conf.example config/runpod.conf
# Edit config/runpod.conf with your SSH settings and paths
```

### Basic Usage
```bash
# Auto-detect running pod and sync workflows
./scripts/pull-workflows.sh   # Download from RunPod
./scripts/push-workflows.sh   # Upload to RunPod
```

### Advanced Usage
```bash
# With options
./scripts/pull-workflows.sh --dry-run --verbose
./scripts/push-workflows.sh --clean

# Manual IP/port specification
./scripts/pull-workflows.sh 192.168.1.100 22 --verbose
./scripts/push-workflows.sh 192.168.1.100 22 --user ubuntu
```

## Commands

### Pull Workflows
```bash
./scripts/pull-workflows.sh [IP_ADDRESS] [SSH_PORT] [OPTIONS]
```
Downloads ComfyUI workflows from RunPod to local `workflows/` directory.

**Options:**
- `-u, --user USER` - SSH username (default: root)
- `-k, --key PATH` - SSH private key path (default: ~/.ssh/id_rsa)
- `-d, --dry-run` - Preview changes without modifying files
- `-v, --verbose` - Enable verbose output
- `-h, --help` - Show help message

### Push Workflows
```bash
./scripts/push-workflows.sh [IP_ADDRESS] [SSH_PORT] [OPTIONS]
```
Uploads local workflows to RunPod instance. **Safe by default** - preserves remote files.

**Options:**
- `-u, --user USER` - SSH username (default: root)
- `-k, --key PATH` - SSH private key path (default: ~/.ssh/id_rsa)
- `-d, --dry-run` - Preview changes without modifying files
- `-v, --verbose` - Enable verbose output
- `--clean` - Delete remote files that don't exist locally
- `-h, --help` - Show help message

## Auto-Detection

Scripts automatically detect running RunPod instances when no IP/port is specified:

**Requirements:**
- `runpodctl` installed and configured with API key
- Exactly one pod running with SSH port exposed

**Example:**
```bash
$ ./scripts/pull-workflows.sh
Auto-detecting running RunPod instance...
Found running pod: 853k3zravetvfo
Detected pod details: 213.173.105.84:49992
Testing SSH connection to root@213.173.105.84:49992...
SSH connection test successful!
...
```

## Configuration

Edit `config/runpod.conf` to set defaults:

```bash
# SSH Connection Details
RUNPOD_SSH_USER="root"
RUNPOD_SSH_KEY_PATH="~/.ssh/id_rsa"

# Paths on your RunPod instance (absolute paths)
RUNPOD_WORKFLOWS_PATH="/workspace/ComfyUI/user/workflows"
```

## Dependencies

- **rsync** - File synchronization
- **ssh** - Secure connections  
- **SSH key** configured for RunPod instance access
- **runpodctl** (optional) - For auto-detection

### Installation
```bash
# macOS
brew install rsync runpodctl

# Ubuntu/Debian
apt-get install rsync openssh-client
```

## Architecture

### Directory Structure
- `scripts/` - Executable bash scripts
- `config/` - Configuration files
- `workflows/` - Local copy of synced ComfyUI workflows

### Shared Library
Scripts use `runpod-common.sh` for shared functionality:
- Configuration loading and validation
- RunPod auto-detection
- SSH connectivity testing
- Remote dependency installation

### Error Handling
- Strict error handling with `set -euo pipefail`
- Dependency validation before execution
- SSH connectivity testing
- Comprehensive parameter validation

## Examples

### Typical Workflow
```bash
# Initial setup
cp config/runpod.conf.example config/runpod.conf
# Edit configuration file

# Download workflows from RunPod
./scripts/pull-workflows.sh

# Make local changes to workflows
# ...

# Upload changes back to RunPod
./scripts/push-workflows.sh --dry-run  # Preview first
./scripts/push-workflows.sh           # Safe upload (preserves remote files)
```

### Multiple RunPods
```bash
# When multiple pods are running, specify manually
./scripts/pull-workflows.sh 192.168.1.100 22001
./scripts/push-workflows.sh 192.168.1.101 22002
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Troubleshooting

### Auto-detection fails
- Ensure `runpodctl` is installed and configured
- Check that exactly one pod is running
- Verify SSH port is exposed on the pod

### SSH connection fails
- Verify SSH key is correct and accessible
- Check IP address and port
- Ensure RunPod instance is running
- Confirm SSH service is enabled on the pod

### rsync errors
- Scripts automatically install rsync on Ubuntu-based pods
- For manual installation: `apt update && apt install -y rsync`