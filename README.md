Exim Mail Submission Agent
==========================

This module will set up on the host running it a mail submission agent (MSA)
using the Exim software.  It will only function as a MSA and in  particular
will  not handle mail transfer or delivery on port 25, even for local delivery.
This is enforced to ensure the most strict security and to run the MSA with the
least priviledges.

It's most useful for dealing with automatic e-mail submission from daemon
processes. With its new pluggable authentication, it can handle external e-mail
submission authorized with a login and password.

Features include:

- Listening on any TCP address (IPv4 and IPv6)
- Running only on port 587
- STARTTLS with externally provided certificates
- Only accepting e-mails from localhost
- DKIM dual signing
- Pluggable authentication
- Missing DNS output for DKIM records

Requirements
------------

- [`terraform-provider-sys`](https://github.com/mildred/terraform-provider-sys)
  needs to be manually installed until i split this provider into better suited
  providers.
- [force-bind](https://github.com/mildred/force-bind-seccomp) needs to be
  installed separately in `/usr/local/bin/force-bind`
- Debian host as several specificities are hardcoded until portability is
  implemented.
- certificates for fqdn installed in standard let's encrypt location

Configuration
-------------

### `sd_prefix`

Systemd prefix to include before the systemd unit names.

### `listen_any`

Boolean (default true) to tell if the MSA should listen to INADDR_ANY (both IPv4
and IPv6)

### `listen_addr`

Boolean (default false) to tell if the MSA should use
[sd-addr.tf](https://registry.terraform.io/modules/mildred/sd-addr.tf/local/latest)
and listen to a generated address made from the unit name.

FIXME: When listen_addr and listen_any are both specified, maybe not every
socket is listened to. With listen_addr, only the IPv6 socket is listening and
IPv4 is not working.

### `listen_port`

Port to listen to. Default is 587 and it is recommended not to change it.

### `fqdn`

The fully qualified domain name to advertise on HELO. Will be a local delivery
domain.

### `relay_from_hosts`

List of domains that are allowed to relay mails even if not authenticated.
Defaults to `localhost` only.

### `selector_rsa`, `selector_ed25519`

DKIM selector (unique id with only letters and digits with no dashes or
underscores) for the RSA and Ed25519 signing schemes.

### `auth`

Boolean to tell if auth is to be enabled or not. Configured with:

- `auth_sockapi`: the socket to use for auth. Can be a socket file or a network
  address in the form `inet:HOST:PORT` where `HOST` can be a hostname, an IPv4
  address or an IPv6 address enclosed in brackets. See
  [Exim docs](http://exim.org/exim-html-4.91/doc/html/spec_html/ch11.html) for
  more details.

Auth protocol is implemented in
[accountserver](https://github.com/mildred/accountserver/). It uses Exim
`${readsocket{}{}}`. When needing to authenticate, it opens the socket file
writes a simple request string and expects a response. The request is
query-string like with the following fields:

- `req=checkauth`
- `user64=` base64 encoded user name
- `pass64=` base64 encoded password
- `true=` value to return if auth is successful
- `false=` value to return if auth is failed

Example exchange:

    > req=checkauth&user64=am9obi5kb2VAZXhhbXBsZS5vcmc=&pass64=ZGkwNUd5V2wxMg==&true=true&false=false
    < true

Note that user and password is base64 encoded and not urlencoded because Exim
only knows how to encode to base64. The base64 alphabet does not use `&` or `#`
so it should be safe to parse with URL libraries.

### `cert_source`

Where to find TLS certificates. Can be `certbot` or `caddy`

If taking certificates from caddy, it is possible to configure the paths:

- `caddy_cert_dir` (string defaults to `/var/lib/caddy/certificates`): location of the
  certificates
- `caddy_acl_dirs` (list) : list of directories that needs to be allowed to the
  exim user using ACL
- `caddy_cert_provider` (string defaults to
  `acme-v02.api.letsencrypt.org-directory`): name of the Caddy certificate
  provider to use.

Output
------

### `dkim_dns`

List of generated DKIM records

### `dns`

List of generated DNS records (DKIM and SPF)

### `sd_addr`

sd-addr.tf address name listened to (if `listen_addr` is true). Else, null.
