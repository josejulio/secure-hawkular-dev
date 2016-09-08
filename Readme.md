# (Quickly) Securing Hawkular communication for testing/development

This is a small ruby script to enable (self-signed) secure communications on a Hawkular server.

This script uses [this](http://www.hawkular.org/hawkular-services/docs/installation-guide/secure-comm.html) and [this](https://some-developer-notes.blogspot.mx/2016/08/consuming-hawkular-api-over-ssl_31.html) guide for securing Hawkular Server on java and for ruby.


## Usage
You must specify your hawkular server path, and this will self-sign the certificates using the configuration found on config.yml.
```bash
bundle exec ruby secure.rb --hawkular PATH_TO_HAWKULAR_SERVER
```
The first call will create a new certificate, if you modify your config and would like to re-create new certificates you can pass the --create (or -c) flag.
```bash
bundle exec ruby secure.rb --create --hawkular PATH_TO_HAWKULAR_SERVER
```
## Notes
This has only been tested on Fedora 24, please let me know if it works or fails on other environments.

## RVM users
You might have to modify config.yml to point openssl_dir to $rvm_path/usr/ssl or make $rvm_path/usr/ssl point to the path show by `openssl version -d`