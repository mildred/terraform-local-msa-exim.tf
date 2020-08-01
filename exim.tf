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
}

module "dkim_ed25519" {
  source    = "./dkim.tf"
  fqdn      = var.fqdn
  algorithm = "ed25519"
  selector  = var.selector_ed25519
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

/*
resource "sys_systemd_unit" "exim" {
  name = "${local.unit_name}.service"
  enable = false
  restart_on = {
    unit = sys_file.exim_service.id
  }
  depends_on = [ sys_systemd_unit.exim4 ]
}

module "exim_proxy_service" {
  source    = "../sd-proxy.tf"
  unit_name = local.unit_name
  bind4     = "0.0.0.0"
  bind6     = "[::]"
  host4     = "$${HOST_${local.unit_name_un}4}"
  host6     = "[$${HOST_${local.unit_name_un}6}]"
  ports = {
    smtp4 = [587, 1587]
    smtp6 = [587, 1587]
  }
}

resource "sys_file" "exim_proxy_service" {
  filename = "/etc/systemd/system/${local.unit_name}-proxy.service"
  content = <<EOF
[Unit]
Description=Exim socket-activated proxy
Requires=addr@${local.unit_name}.service
After=addr@${local.unit_name}.service

[Service]
EnvironmentFile=/run/addr/${local.unit_name}.env
${module.exim_proxy_service.service}


[Install]
WantedBy=multi-user.target
EOF
}

resource "sys_systemd_unit" "exim_proxy" {
  name = "${local.unit_name}-proxy.service"
  start = true
  enable = true
  restart_on = {
    unit = sys_file.exim_proxy_service.id
  }
  depends_on = [ sys_systemd_unit.exim ]
}
*/

