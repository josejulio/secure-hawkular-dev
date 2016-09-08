require 'optparse'
require 'paint'
require 'yaml'
require 'ptools'
require_relative 'wildfly_parser'

def puts_error(message)
  puts Paint[message, :red, :bright]
end

def puts_success(message)
  puts Paint[message, :green, :bright]
end

def run_command(command)
  puts 'Running: ' << Paint[command, :green, :bright]
  system command || exit!(1)
end

def delete_if_exists(files)
  files.each do |file|
    if File.exist? file
      puts 'Deleting:' << Paint[file, :red]
      File.delete file
    end
  end
end

create = false
required_commands = %w(java c_rehash keytool openssl)
hawkular_server = nil

OptionParser.new do |parser|
  parser.on('-c', '--create', 'Creates a new self signed certificate') do
    create = true
  end
  parser.on('--hawkular PATH', 'Specify hawkular server path (e.g. standalone.xml)') do |path|
    hawkular_server = path
  end
end.parse!

raise 'Specify hawkular server path (e.g. standalone.xml) --hawkular' if hawkular_server.nil?
raise "Hawkular path can't be resolved (#{hawkular_server})" unless Dir.exist? hawkular_server

config = YAML.load_file('config.yml')

commands = required_commands.map do |command|
  command_path = File.which(command)
  puts_error "#{command} not found, please install" if command_path.nil?
  [command, command_path]
end.to_h
exit! 1 if commands.values.include? nil

if create
  delete_if_exists [config['keystore_file'], config['cert_der_file'], config['cert_pem_file']]
end

unless File.exist? config['keystore_file']
  delete_if_exists [config['cert_der_file']]
  san_config = config['cert']['san']
  san = ''
  san << 'ip:' << san_config['ip'].join(',ip:') unless san_config['ip'].empty?
  san << ',' unless san.empty?
  san << 'dns:' << san_config['dns'].join(',dns:') unless san_config['dns'].empty?
  san = "-ext san=#{san}" unless san.empty?
  run_command "#{commands['keytool']} -genkey -keystore #{config['keystore_file']} -alias #{config['alias']}"\
              " -dname \"#{config['cert']['dname']}\" -keyalg RSA -storepass #{config['keystore_password']}"\
              " -keypass #{config['keystore_password']} -validity 36500 #{san}"
  FileUtils.cp config['keystore_file'], "#{hawkular_server}/standalone/configuration"
end

unless File.exist? config['cert_der_file']
  delete_if_exists [config['cert_pem_file']]
  # find java_home
  if config['java_home'].nil?
    java_home = `#{commands['java']} -XshowSettings 2>&1 > /dev/null | grep java.home`
    parsed = /\s*java.home\s+=\s+(.+)/.match(java_home)
    raise 'Could not find java_home please specify it on config.yml' unless parsed.size == 2
    config['java_home'] = parsed[1]
  end
  run_command "#{commands['keytool']} -export -alias #{config['alias']} -file #{config['cert_der_file']}"\
              " -storepass #{config['keystore_password']} -keystore #{config['keystore_file']}"
  run_command "sudo #{commands['keytool']} -delete -keystore #{config['java_home']}/lib/security/cacerts"\
              " -alias #{config['alias']} -storepass #{config['java_store_pass']} ||:"
  run_command "sudo #{commands['keytool']} -import -keystore #{config['java_home']}/lib/security/cacerts -noprompt"\
              " -alias #{config['alias']} -storepass #{config['java_store_pass']} -file #{config['cert_der_file']}"
end

unless File.exist? config['cert_pem_file']
  if config['openssl_dir'].nil?
    openssl_output = `openssl version -d`
    parsed = /OPENSSLDIR:\s+\"(.+)\"/.match(openssl_output)
    raise 'Could not find openssl_dir please specify it on config.yml' unless parsed.size == 2
    config['openssl_dir'] = parsed[1]
  end
  cert_dir = "#{config['openssl_dir']}/certs/"
  run_command "#{commands['openssl']} x509 -inform der -in #{config['cert_der_file']} -out #{config['cert_pem_file']}"
  run_command "sudo cp #{config['cert_pem_file']} #{cert_dir}"
  run_command "#{commands['c_rehash']} #{cert_dir}"
  run_command "#{commands['c_rehash']} -old -n #{cert_dir}"
end

parser = SecureDevEnvironment::WildflyParser.new hawkular_server
parser.configure_for_security config
parser.sync
