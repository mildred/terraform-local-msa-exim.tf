variable "fqdn" {
  description = "Fully qualified domain name"
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

locals {
  unit_name = "${var.sd_prefix}msa-exim"
  unit_name_un = replace(local.unit_name, "-", "_")
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
tls_certificate  = /etc/letsencrypt/live/${var.fqdn}/fullchain.pem
tls_privatekey   = /etc/letsencrypt/live/${var.fqdn}/privkey.pem

daemon_smtp_ports = <, BIND_PORTS
local_interfaces  = <, BIND_ADDRS

domainlist local_domains    = ${var.fqdn}
domainlist relay_to_domains =
hostlist   relay_from_hosts = localhost

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

[Socket]
ListenStream=[::]:587
ListenStream=0.0.0.0:587
BindIPv6Only=ipv6-only

[Install]
WantedBy=multi-user.target

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

[Service]
User=Debian-exim
Group=Debian-exim
ExecStartPre=+/usr/bin/mkdir -p /var/spool/${local.unit_name} /var/log/${local.unit_name}
ExecStartPre=+/usr/bin/chown Debian-exim:Debian-exim /var/spool/${local.unit_name} /var/log/${local.unit_name}
ExecStart=/bin/sh -c ' \
  exec /usr/local/bin/force-bind \
  -m [::]:587/0=sd-0 \
  -m 0.0.0.0:587/0=sd-1 \
  /usr/sbin/exim4 \
    -C ${sys_file.exim_conf.filename} \
    -DBIND_PORTS=587 \
    -DBIND_ADDRS=127.0.0.1,[::1] \
    -DDKIM_SELECTORS=${var.selector_rsa},${var.selector_ed25519} \
    -DUID=$(id -u Debian-exim) -DGID=$(id -g Debian-exim) \
    -bdf -q1h \
'

CONF
}

resource "sys_systemd_unit" "exim4" {
  name = "exim4.service"
  start = false
  enable = false
}

resource "sys_systemd_unit" "exim" {
  name = "${local.unit_name}.socket"
  enable = true
  start = true
  restart_on = {
    service_unit = sys_file.exim_service.id
    socket_unit = sys_file.exim_socket.id
  }
  depends_on = [ sys_systemd_unit.exim4 ]
}

locals {
  spf = "${var.fqdn}. TXT \"v=spf1 +a:${var.fqdn} -all\""
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
