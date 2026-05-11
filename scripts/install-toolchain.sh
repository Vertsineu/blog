#!/usr/bin/env bash
set -euo pipefail

repo="${BLOG_TOOLCHAIN_REPO:-Vertsineu/blog}"
tag="${BLOG_TOOLCHAIN_TAG:-blog-toolchain-linux-amd64}"
install_dir="${BLOG_TOOLCHAIN_INSTALL_DIR:-$HOME/.local/bin}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$install_dir"

download_asset() {
  local asset="$1"
  local url="https://github.com/${repo}/releases/download/${tag}/${asset}"

  echo "Downloading ${url}"
  curl -fsSL "$url" -o "$tmp_dir/$asset"
}

download_asset "hugo-linux-amd64.tar.gz"
download_asset "typst-linux-amd64.tar.gz"

tar -xzf "$tmp_dir/hugo-linux-amd64.tar.gz" -C "$tmp_dir"
tar -xzf "$tmp_dir/typst-linux-amd64.tar.gz" -C "$tmp_dir"

install -m 0755 "$tmp_dir/bin/hugo" "$install_dir/hugo"
install -m 0755 "$tmp_dir/bin/typst" "$install_dir/typst"

echo "Installed hugo and typst to ${install_dir}"
"$install_dir/hugo" version
"$install_dir/typst" --version
