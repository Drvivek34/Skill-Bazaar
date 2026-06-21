---
name: ci-cd-troubleshooter
description: Use when analyzing failing build/test logs in Github Actions, GitLab, or Jenkins, and fixing pipeline configuration files.
---

# CI/CD Troubleshooting Instructions
1. Fetch build stdout and inspect lines containing 'failed', 'error', or exit codes.
2. Locate the failing step and match it to package version dependencies.
3. Validate node_modules, bundler caches, or lockfiles.
4. Correct YAML syntax errors in configuration files.
5. Recommend changes to pipeline caching options to accelerate build times.

