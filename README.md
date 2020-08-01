Exim Mail Submission Agent
==========================

This module will set up on the host running it a mail submission agent (MSA)
using the Exim software.  It will only function as a MSA and in  particular
will  not handle mail transfer or delivery on port 25, even for local delivery.
This is enforced to ensure the most strict security and to run the MSA with the
least priviledges.

Features include:

- Running only on port 587
- STARTTLS with externally provided certificates
- Only accepting e-mails from localhost
- DKIM dual signing

Missing features:

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

### `fqdn`

The fully qualified domain name to advertise on HELO. Will be a local delivery
domain.

### `selector_rsa`, `selector_ed25519`

DKIM selector (unique id with only letters and digits with no dashes or
underscores) for the RSA and Ed25519 signing schemes.

### `sd_prefix`

Systemd prefix to include before the systemd unit names.


