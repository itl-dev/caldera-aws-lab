#!/bin/bash
# ============================================================
#  CloudShell bootstrap for the CALDERA AWS lab.
#  Run once per CloudShell session:  source ./setup.sh
#
#  - Installs Terraform into ~/bin (persists in CloudShell's 1GB /home)
#  - Sets a SHARED provider plugin cache so `terraform init` does NOT
#    blow past CloudShell's 1GB home quota.
#  Use `source` (not bash) so the PATH/env changes apply to your shell.
# ============================================================
set -e
TF_VERSION="${TF_VERSION:-1.9.8}"

# --- Terraform into ~/bin ---
mkdir -p "$HOME/bin"
if ! command -v terraform >/dev/null 2>&1 || [ "$(terraform version -json 2>/dev/null | grep -o "$TF_VERSION")" != "$TF_VERSION" ]; then
  echo "Installing Terraform $TF_VERSION ..."
  tmp="$(mktemp -d)"
  curl -fsSLo "$tmp/tf.zip" "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  unzip -o "$tmp/tf.zip" -d "$tmp" >/dev/null
  mv "$tmp/terraform" "$HOME/bin/terraform"
  rm -rf "$tmp"
fi

# --- PATH (persist for future sessions) ---
grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH=$HOME/bin:$PATH' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"

# --- shared provider cache (CRITICAL on CloudShell's 1GB /home) ---
mkdir -p "$HOME/.terraform.d/plugin-cache"
grep -q TF_PLUGIN_CACHE_DIR "$HOME/.bashrc" 2>/dev/null || \
  echo 'export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache' >> "$HOME/.bashrc"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

echo
echo "Ready: $(terraform version | head -1)"
echo "TF_PLUGIN_CACHE_DIR=$TF_PLUGIN_CACHE_DIR"
echo "Next:  terraform init  &&  terraform apply"
