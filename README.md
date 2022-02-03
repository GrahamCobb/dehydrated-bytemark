# dehydrated-bytemark

Dehydrated hook script to handle DNS-01 challenge using Bytemark DNS servers.
This might also be usable with other tinydns/djbdns servers.

 * `djbdns-modify` - script to make modifications to djbdns data files
 * `hook.sh` - dehydrated hook script

## Bytemark

Bytemark are a UK cloud hosting company (https://bytemark.co.uk/).
They offer a DNS server service for their hosting clients, which uses `djbdns` (also known as `tinydns`).
The DNS data files are stored on the client's cloud server and uploaded to the Bytemark DNS servers when required.

These scripts can be used to deploy DNS-01 ACME challenges for dehydrated to generate certitcates.

## Credits
Adapted from https://github.com/sebastiansterk/dns-01-manual/blob/master/hook.sh
which is from https://github.com/lukas2511/dehydrated/blob/master/docs/examples/hook.sh
