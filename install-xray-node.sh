#!/usr/bin/env bash

set -euo pipefail

DOWNLOAD_BASE_URL="https://node.v233.xyz"
IMAGE_TAR_NAME="xrayr-reality-image.tar"
TEMPLATE_TAR_NAME="xray-node-template.tar.gz"
DEPLOY_ROOT="/var/www/xray"
CONFIG_FILE="${DEPLOY_ROOT}/config/config.yml"
COMPOSE_FILE="${DEPLOY_ROOT}/docker-compose.yml"
CONTAINER_NAME="ustc"
IMAGE_NAME="v2xu/xrayr-reality:latest"
DOCKER_KEYRING_DIR="/etc/apt/keyrings"
DOCKER_KEYRING_FILE="${DOCKER_KEYRING_DIR}/docker.asc"
DOCKER_SOURCES_FILE="/etc/apt/sources.list.d/docker.sources"
TMP_DIR=""
DOWNLOAD_USERNAME=""
DOWNLOAD_PASSWORD=""
NODE_ID=""
CONTAINER_NAME_INPUT=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

require_sudo_if_needed() {
  if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "当前不是 root，且系统里没有 sudo，无法继续。"
      exit 1
    fi

    if ! sudo -v; then
      echo "sudo 验证失败，无法继续。"
      exit 1
    fi
  fi
}

ensure_debian_like() {
  if [[ ! -r /etc/os-release ]]; then
    echo "无法识别系统版本，缺少 /etc/os-release。"
    exit 1
  fi

  if ! grep -Eq '^(ID|ID_LIKE)=.*(debian|ubuntu)' /etc/os-release; then
    echo "当前系统不是 Debian / Ubuntu 系，已停止。"
    exit 1
  fi
}

prompt_inputs() {
  echo "说明: 这里要输入的是 node.v233.xyz 的下载认证，不是 SSH 登录密码。"

  read -r -p "请输入 node.v233.xyz 下载用户名: " DOWNLOAD_USERNAME
  if [[ -z "${DOWNLOAD_USERNAME}" ]]; then
    echo "下载用户名不能为空，已停止。"
    exit 1
  fi

  read -r -s -p "请输入 node.v233.xyz 下载密码: " DOWNLOAD_PASSWORD
  echo
  if [[ -z "${DOWNLOAD_PASSWORD}" ]]; then
    echo "下载密码不能为空，已停止。"
    exit 1
  fi

  read -r -p "请输入当前节点的 NodeID: " NODE_ID
  if [[ ! "${NODE_ID}" =~ ^[0-9]+$ ]]; then
    echo "NodeID 必须是纯数字，已停止。"
    exit 1
  fi

  read -r -p "请输入当前容器名: " CONTAINER_NAME_INPUT
  if [[ ! "${CONTAINER_NAME_INPUT}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    echo "容器名格式不合法，已停止。"
    exit 1
  fi

  CONTAINER_NAME="${CONTAINER_NAME_INPUT}"
}

configure_docker_apt_repository() {
  local codename
  local arch

  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  arch="$(dpkg --print-architecture)"

  if [[ -z "${codename}" || -z "${arch}" ]]; then
    echo "无法识别 Docker 仓库所需的系统信息，已停止。"
    exit 1
  fi

  run_as_root install -m 0755 -d "${DOCKER_KEYRING_DIR}"
  run_as_root curl -fsSL https://download.docker.com/linux/debian/gpg -o "${DOCKER_KEYRING_FILE}"
  run_as_root chmod a+r "${DOCKER_KEYRING_FILE}"

  run_as_root tee "${DOCKER_SOURCES_FILE}" >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: ${DOCKER_KEYRING_FILE}
EOF
}

ensure_packages() {
  local packages=(
    ca-certificates
    curl
    tar
    gzip
    sed
    grep
    coreutils
  )

  export DEBIAN_FRONTEND=noninteractive
  run_as_root apt-get update
  run_as_root apt-get install -y "${packages[@]}"

  if ! command -v awk >/dev/null 2>&1; then
    if apt-cache show gawk >/dev/null 2>&1; then
      run_as_root apt-get install -y gawk
    elif apt-cache show mawk >/dev/null 2>&1; then
      run_as_root apt-get install -y mawk
    else
      echo "系统里缺少 awk，且未找到可安装的 gawk/mawk，已停止。"
      exit 1
    fi
  fi

  if ! docker compose version >/dev/null 2>&1; then
    configure_docker_apt_repository
    run_as_root apt-get update
    run_as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  run_as_root systemctl enable --now docker
}

make_tmp_dir() {
  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT
}

cleanup() {
  unset DOWNLOAD_PASSWORD

  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}

download_with_auth() {
  local url="$1"
  local output_path="$2"

  curl --fail --location --silent --show-error \
    --user "${DOWNLOAD_USERNAME}:${DOWNLOAD_PASSWORD}" \
    "${url}" \
    --output "${output_path}"
}

download_assets() {
  local image_tar="${TMP_DIR}/${IMAGE_TAR_NAME}"
  local image_sha="${TMP_DIR}/${IMAGE_TAR_NAME}.sha256"
  local template_tar="${TMP_DIR}/${TEMPLATE_TAR_NAME}"
  local template_sha="${TMP_DIR}/${TEMPLATE_TAR_NAME}.sha256"

  echo "开始下载镜像包和模板包，请稍等。"

  download_with_auth "${DOWNLOAD_BASE_URL}/${IMAGE_TAR_NAME}" "${image_tar}"
  download_with_auth "${DOWNLOAD_BASE_URL}/${IMAGE_TAR_NAME}.sha256" "${image_sha}"
  download_with_auth "${DOWNLOAD_BASE_URL}/${TEMPLATE_TAR_NAME}" "${template_tar}"
  download_with_auth "${DOWNLOAD_BASE_URL}/${TEMPLATE_TAR_NAME}.sha256" "${template_sha}"

  verify_checksum "${image_tar}" "${image_sha}"
  verify_checksum "${template_tar}" "${template_sha}"
}

verify_checksum() {
  local file_path="$1"
  local sha_path="$2"
  local expected_sha
  local actual_sha

  expected_sha="$(tr -d '[:space:]' < "${sha_path}")"
  actual_sha="$(sha256sum "${file_path}" | awk '{print $1}')"

  if [[ -z "${expected_sha}" ]]; then
    echo "校验文件 ${sha_path} 为空，已停止。"
    exit 1
  fi

  if [[ "${expected_sha}" != "${actual_sha}" ]]; then
    echo "文件校验失败: ${file_path}"
    echo "期望: ${expected_sha}"
    echo "实际: ${actual_sha}"
    exit 1
  fi
}

backup_existing_deploy() {
  if [[ -e "${COMPOSE_FILE}" || -e "${CONFIG_FILE}" ]]; then
    local backup_dir="/var/www/xray-backup-$(date +%Y%m%d%H%M%S)"
    echo "检测到现有部署文件，先备份到 ${backup_dir}"
    run_as_root mkdir -p "${backup_dir}"

    if [[ -d "${DEPLOY_ROOT}" ]]; then
      run_as_root cp -a "${DEPLOY_ROOT}/." "${backup_dir}/"
    fi
  fi
}

install_template() {
  run_as_root mkdir -p "${DEPLOY_ROOT}"
  run_as_root find "${DEPLOY_ROOT}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  run_as_root tar -xzf "${TMP_DIR}/${TEMPLATE_TAR_NAME}" -C "${DEPLOY_ROOT}"
}

load_image() {
  echo "开始导入 Docker 镜像，请稍等。"
  run_as_root docker load -i "${TMP_DIR}/${IMAGE_TAR_NAME}"
}

generate_reality_keys() {
  local key_output

  key_output="$(run_as_root docker run --rm --entrypoint /usr/local/bin/XrayR "${IMAGE_NAME}" x25519)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/^Private key:/ {print $2}')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/^Public key:/ {print $2}')"

  if [[ -z "${REALITY_PRIVATE_KEY}" || -z "${REALITY_PUBLIC_KEY}" ]]; then
    echo "Reality 密钥生成失败，已停止。"
    exit 1
  fi
}

update_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "缺少配置文件 ${CONFIG_FILE}，已停止。"
    exit 1
  fi

  run_as_root sed -i -E \
    "0,/NodeID:[[:space:]]*[0-9]+(.*)$/s//NodeID: ${NODE_ID}\\1/" \
    "${CONFIG_FILE}"

  run_as_root sed -i -E \
    "0,/RealityPrivateKey:[[:space:]]*\"[^\"]*\"(.*)$/s//RealityPrivateKey: \"${REALITY_PRIVATE_KEY}\"\\1/" \
    "${CONFIG_FILE}"

  if [[ -f "${COMPOSE_FILE}" ]]; then
    run_as_root sed -i -E \
      "0,/container_name:[[:space:]]*[^\r\n#]+/s//container_name: ${CONTAINER_NAME}/" \
      "${COMPOSE_FILE}"
  fi
}

start_container() {
  echo "开始启动容器。"
  (
    cd "${DEPLOY_ROOT}"
    run_as_root docker compose up -d
  )
}

show_result() {
  echo
  echo "部署完成，下面是关键结果。"
  echo
  run_as_root docker ps --filter "name=${CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  echo
  echo "Reality Private Key:"
  echo "${REALITY_PRIVATE_KEY}"
  echo
  echo "Reality Public Key (pbk):"
  echo "${REALITY_PUBLIC_KEY}"
  echo
  echo "请复制下面这段 SSPanel 自定义配置 JSON:"
  cat <<EOF
{
  "pbk": "${REALITY_PUBLIC_KEY}",
  "sid": "a1b2c3d4",
  "sni": "www.apple.com",
  "fp": "chrome",
  "flow": "xtls-rprx-vision",
  "offset_port_node": "8443",
  "network": "tcp",
  "enable_vless": "1"
}
EOF
  echo
  echo "部署目录: ${DEPLOY_ROOT}"
  echo "配置文件: ${CONFIG_FILE}"
}

main() {
  ensure_debian_like
  require_sudo_if_needed
  prompt_inputs
  make_tmp_dir
  ensure_packages
  download_assets
  backup_existing_deploy
  install_template
  load_image
  generate_reality_keys
  update_config
  start_container
  show_result
}

main "$@"
