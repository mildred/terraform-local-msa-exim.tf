variable "fqdn" {
  description = "Fully qualified domain name"
}

variable "relay_from_hosts" {
  type = list
  default = ["localhost"]
}

variable "relay_from_addrs" {
  type = list
  default = []
}

variable "safe_networks" {
  type = list
  default = []
}

variable "sd_prefix" {
  description = "Systemd unit prefix"
  type        = string
  default     = ""
}

variable "selector_rsa" {
  default = "rsa1"
}

variable "selector_ed25519" {
  default = "ed1"
}

variable "cert_source" {
  description = "Where to find certificates (certbot, caddy)"
  type        = string
  default     = "certbot"
}

variable "caddy_cert_dir" {
  description = "When using cert_source=caddy, where are the certificates"
  type        = string
  default     = "/var/lib/caddy/certificates"
  // Could be also at var/lib/caddy/.local/share/caddy/certificates
}

variable "caddy_acl_dirs" {
  description = "Which additional directories to give ACL access to"
  type        = list
  default     = []
  // Could be also at var/lib/caddy/.local/share/caddy/certificates
}

variable "caddy_cert_provider" {
  description = "When using cert_source=caddy, the certificate subdirectory"
  type        = string
  default     = "acme-v02.api.letsencrypt.org-directory"
}

variable "auth" {
  description = "Enable authentication"
  default     = false
}

variable "auth_sockapi" {
  description = "Authentication API socket"
  type        = string
}

variable "listen_any" {
  type  = bool
  default = true
}

variable "listen_addr" {
  type  = bool
  default = false
}

variable "listen_port" {
  description = "Port to listen to if not 587"
  type = number
  default = 587
}

variable "debug" {
  type = bool
  default = false
}

variable "debug_categories" {
  type = list
  default = ["+all"]
}

locals {
  unit_name = "${var.sd_prefix}msa-exim"
  unit_name_un = replace(local.unit_name, "-", "_")

  tls_certificate = lookup({
    certbot = "/etc/letsencrypt/live/${var.fqdn}/fullchain.pem"
    caddy   = "${var.caddy_cert_dir}/${var.caddy_cert_provider}/${var.fqdn}/${var.fqdn}.crt"
  }, var.cert_source, "/etc/ssl/certs/${var.fqdn}.pem")

  tls_privatekey  = lookup({
    certbot = "/etc/letsencrypt/live/${var.fqdn}/privkey.pem"
    caddy   = "${var.caddy_cert_dir}/${var.caddy_cert_provider}/${var.fqdn}/${var.fqdn}.key"
  }, var.cert_source, "/etc/ssl/private/${var.fqdn}.pem")

  acl_files = lookup({
    certbot = "/etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/live/${var.fqdn}"
    caddy   = "${dirname(var.caddy_cert_dir)} ${var.caddy_cert_dir} ${var.caddy_cert_dir}/${var.caddy_cert_provider} /${var.caddy_cert_dir}/${var.caddy_cert_provider}/${var.fqdn} ${join(" ", var.caddy_acl_dirs)}"
  }, var.cert_source, "")

  #auth_exec_start_pre = var.auth ? "ExecStartPre=-/usr/local/bin/http-config-fs --file credentials.json ${var.auth_credentials_url} /run/${local.unit_name}/credentials" : ""
  #auth_exec_stop_post = var.auth ? "ExecStopPost=-/usr/bin/fusermount -u /run/${local.unit_name}/credentials/" : ""
  #auth_define_credentials = var.auth ? "-DCREDENTIALS_JSON_FILE=/run/${local.unit_name}/credentials/credentials.json" : ""
  auth_exec_start_pre = ""
  auth_exec_stop_post = ""
  auth_define_credentials = var.auth ? "-DCREDENTIALS_SOCKET=${var.auth_sockapi}" : ""
}

resource "sys_package" "exim" {
  type = "deb"
  name = "exim4"
}

module "dkim_rsa" {
  source    = "./dkim.tf"
  fqdn      = var.fqdn
  algorithm = "rsa"
  selector  = var.selector_rsa
  user      = "Debian-exim"
  group     = "Debian-exim"
}

module "dkim_ed25519" {
  source    = "./dkim.tf"
  fqdn      = var.fqdn
  algorithm = "ed25519"
  selector  = var.selector_ed25519
  user      = "Debian-exim"
  group     = "Debian-exim"
}

resource "sys_file" "exim_conf" {
  filename = "/etc/${local.unit_name}.conf"
  content  = <<CONFIG

primary_hostname = ${var.fqdn}
exim_user        = UID
exim_group       = GID
spool_directory  = /var/spool/${local.unit_name}
log_file_path    = /var/log/${local.unit_name}/%slog
tls_certificate  = ${local.tls_certificate}
tls_privatekey   = ${local.tls_privatekey}
tls_on_connect_ports = 4465

daemon_smtp_ports = <, BIND_PORTS
local_interfaces  = <, BIND_ADDRS

domainlist local_domains    = ${var.fqdn}
domainlist relay_to_domains =
hostlist   relay_from_hosts = <; ${join(" ; ", var.relay_from_hosts)} ; $${env{EXIM_EXTRA_RELAY_FROM_HOSTS}{$value}}
hostlist   safe_networks    = <; ; ${join(" ; ", var.safe_networks)}

${file("${path.module}/msa-exim.conf")}

CONFIG
}

resource "sys_file" "exim_socket" {
  filename = "/etc/systemd/system/${local.unit_name}.socket"
  content = <<CONF
[Unit]
Description=EXIM Submission server
After=network.target
Conflicts=exim4.service
${var.listen_addr ? "GenerateAddr=${local.unit_name}" : ""}
${var.listen_addr ? "Requires=addr@${local.unit_name}.service" : ""}

[Socket]
${var.listen_addr ? "ListenStream=[$${addr6@${local.unit_name}}]:${var.listen_port}" : ""}
${var.listen_addr ? "ListenStream=$${addr4@${local.unit_name}}:${var.listen_port}" : ""}
${var.listen_addr ? "BindIPv6Only=both" : ""}

${var.listen_any  ? "ListenStream=[::]:${var.listen_port}" : ""}
${var.listen_any  ? "ListenStream=0.0.0.0:${var.listen_port}" : ""}
${var.listen_any  ? "BindIPv6Only=ipv6-only" : ""}

[Install]
WantedBy=multi-user.target
GeneratedAddrWantedBy=multi-user.target

CONF
}

resource "sys_file" "exim_service" {
  filename = "/etc/systemd/system/${local.unit_name}.service"
  content = <<CONF
[Unit]
Description=EXIM Submission server
After=network.target
Conflicts=exim4.service
Requires=${local.unit_name}.socket
After=${local.unit_name}.socket
${join("\n", [for a in var.relay_from_addrs:
  "Requires=addr@${a}.service\nAfter=addr@${a}.service"
])}

[Service]
User=Debian-exim
Group=Debian-exim
ExecStartPre=+/usr/bin/mkdir -p \
  /var/spool/${local.unit_name} \
  /var/log/${local.unit_name} \
  /run/${local.unit_name}/credentials
ExecStartPre=+/usr/bin/chown Debian-exim:Debian-exim /var/spool/${local.unit_name} /var/log/${local.unit_name}
ExecStartPre=+/usr/bin/setfacl -m u:Debian-exim:rX,g:Debian-exim:rX ${local.tls_certificate} ${local.tls_privatekey} ${local.acl_files}
${local.auth_exec_start_pre}

${join("\n", [for a in var.relay_from_addrs:
  "EnvironmentFile=/run/addr/${a}.env"
])}

ExecStartPre=/bin/echo "Logs are in /var/log/${local.unit_name}/"
ExecStart=/bin/sh -c ' \
  export EXIM_EXTRA_RELAY_FROM_HOSTS=\"${join(" ; ", [for a in var.relay_from_addrs:
    "$${HOST_${replace(a, "-", "_")}4} ; $${HOST_${replace(a, "-", "_")}6}"
  ])}\"; \
  exec /usr/local/bin/force-bind \
  -v -m [::]:587/0=sd-0 \
  -v -m 0.0.0.0:587/0=sd-1 \
  /usr/sbin/exim4 \
    ${var.debug ? "-d${join(",", var.debug_categories)}" : ""} \
    -C ${sys_file.exim_conf.filename} \
    ${local.auth_define_credentials} \
    -DBIND_PORTS=587 \
      -DBIND_ADDRS=::1,127.0.0.1 \
    -DDKIM_SELECTORS=${var.selector_rsa},${var.selector_ed25519} \
    -DUID=$(id -u Debian-exim) -DGID=$(id -g Debian-exim) \
    -bdf -q1h \
'

${local.auth_exec_stop_post}

CONF
}

resource "sys_systemd_unit" "exim4" {
  name = "exim4.service"
  start = false
  mask = true
}

resource "sys_systemd_unit" "exim" {
  name = "${local.unit_name}.socket"
  enable = true
  start = true
  restart_on = {
    service_unit = sys_file.exim_service.id
    socket_unit = sys_file.exim_socket.id
    config = sys_file.exim_conf.id
  }
  depends_on = [ sys_systemd_unit.exim4 ]
}

locals {
  spf = "${var.fqdn}. IN TXT \"v=spf1 +a:${var.fqdn} -all\""
  rel_spf = "@ IN TXT \"v=spf1 +a:${var.fqdn} -all\""
}

output "dkim_dns" {
  value = [
    module.dkim_rsa.dns,
    module.dkim_ed25519.dns,
  ]
}

output "dns" {
  value = [
    module.dkim_rsa.dns,
    module.dkim_ed25519.dns,
    local.spf,
  ]
}

output "rel_dns" {
  value = [
    module.dkim_rsa.rel_dns,
    module.dkim_ed25519.rel_dns,
    local.rel_spf,
  ]
}

output "sd_addr" {
  value = var.listen_addr ? local.unit_name : null
}
