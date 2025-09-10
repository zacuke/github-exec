# github-exec

Execute binaries directly from GitHub releases with zero dependencies (just curl).

## Installation
```bash
curl -sSL https://raw.githubusercontent.com/zacuke/github-exec/main/install.sh | bash
```

## Usage
```bash
github-exec [OPTIONS] <user/repo> <executable> [args...]

Options:
  --version VERSION    Use specific version instead of latest
  --force              Force redownload
  --help               Show this help
  --cache-dir DIR      Custom cache directory (default: ~/.cache/github-exec)
  --no-cache           Disable caching
```

## Portable One-liner (no install):
```bash
curl -sSL https://raw.githubusercontent.com/zacuke/github-exec/main/github-exec.sh | bash -s -- <user/repo> <executable> [args...]
```
### Shortened url:
```bash
curl -sSL https://effectivesln.com/github-exec.sh | bash -s -- <user/repo> <executable> [args...]
```

