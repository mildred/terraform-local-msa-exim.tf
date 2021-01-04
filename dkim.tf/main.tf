variable "fqdn" {
}

variable "selector" {
}

variable "user" {
}

variable "group" {
}

variable "algorithm" {
  default = "rsa"
}

resource "sys_shell_script" "dkim_key_ed25519" {
  count = (var.algorithm == "ed25519" ? 1 : 0)
  working_directory = "/etc"
  create = <<SCRIPT
    set -e
    fqdn=${var.fqdn}
    mkdir -p /etc/dkim/$fqdn
    cd /etc/dkim/$fqdn

    (
      openssl genpkey -algorithm ed25519 -out ${var.selector}.private
      openssl pkey -outform DER -pubout -in ${var.selector}.private | tail -c +13 | base64 > ${var.selector}.public
      chown ${var.user}:${var.group} ${var.selector}.private ${var.selector}.public
    ) >&2

    cat ${var.selector}.public
SCRIPT
  read = <<SCRIPT
    fqdn=${var.fqdn}
    mkdir -p /etc/dkim/$fqdn
    cd /etc/dkim/$fqdn

    cat ${var.selector}.public 2>/dev/null
SCRIPT
  delete = <<SCRIPT
    fqdn=${var.fqdn}
    rm -f /etc/dkim/$fqdn/${var.selector}.*
SCRIPT
}

resource "sys_shell_script" "dkim_key_rsa" {
  count = (var.algorithm == "rsa" ? 1 : 0)
  working_directory = "/etc"
  create = <<SCRIPT
    set -e
    fqdn=${var.fqdn}
    mkdir -p /etc/dkim/$fqdn
    cd /etc/dkim/$fqdn

    (
      openssl genrsa -out ${var.selector}.private 2048
      openssl rsa -in ${var.selector}.private -out /dev/stdout -pubout -outform PEM | tail -n +2 | head -n -1 | xargs -n 1 printf %s > ${var.selector}.public
    ) >&2

    cat ${var.selector}.public
SCRIPT
  read = <<SCRIPT
    fqdn=${var.fqdn}
    mkdir -p /etc/dkim/$fqdn
    cd /etc/dkim/$fqdn

    cat ${var.selector}.public 2>/dev/null
SCRIPT
  delete = <<SCRIPT
    fqdn=${var.fqdn}
    rm -f /etc/dkim/$fqdn/${var.selector}.{public,private}
SCRIPT
}

data "sys_file" "pubkey" {
  filename = "/etc/dkim/${var.fqdn}/${var.selector}.public"
  depends_on = [ sys_shell_script.dkim_key_ed25519, sys_shell_script.dkim_key_rsa ]
}

output "keyfile" {
  value = "/etc/dkim/${var.fqdn}/${var.selector}.private"
}

output "pubkey" {
  value = data.sys_file.pubkey.content
}

output "dns" {
  value = "${var.selector}._domainkey.${var.fqdn}. TXT \"v=DKIM1; k=${var.algorithm}; p=${chomp(data.sys_file.pubkey.content)}\""
}
