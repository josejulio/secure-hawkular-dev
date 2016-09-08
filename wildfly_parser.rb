require 'nokogiri'

module SecureDevEnvironment
  # Parses wildfly standalone.xml file to add some nodes used to secure the communication.
  class WildflyParser
    def initialize(server_path)
      @server_path = server_path
      @doc = File.open("#{server_path}/standalone/configuration/standalone.xml") { |f| Nokogiri::XML(f) }
      @doc.at_xpath('/xmlns:server/xmlns:profile').children.each do |element|
        check_subsystem_namespace element if element.name == 'subsystem'
      end
    end

    def check_subsystem_namespace(subsystem)
      @undertow_ns = subsystem.namespace.href if subsystem.namespace.href.include? 'undertow'
      @hawkular_agent_ns = subsystem.namespace.href if subsystem.namespace.href.include? 'hawkular.agent'
    end

    def configure_for_security(config = nil)
      add_security_realm config
      add_https_listener
      turn_on_ssl
    end

    def add_security_realm(config)
      alias_name = config['alias']
      keystore_password = config['keystore_password']
      key_password = config['key_password']
      realm = @doc.xpath(
        '//xmlns:server/xmlns:management/xmlns:security-realms/xmlns:security-realm[@name=\'UndertowRealm\']'
      )
      realm.each(&:remove)
      realms = @doc.xpath('//xmlns:server/xmlns:management/xmlns:security-realms/xmlns:security-realm')
      realms.first.add_previous_sibling security_realm_text_node(alias_name, keystore_password, key_password)
    end

    def add_https_listener
      @doc.xpath('//xmlns:server[@name=\'default-server\']/xmlns:https-listener').each(&:remove)
      default_server = @doc.at_xpath('//undertow:server[@name=\'default-server\']', 'undertow' => @undertow_ns)
      default_server.add_child '<https-listener name="https" security-realm="UndertowRealm" socket-binding="https"/>\n'
    end

    def turn_on_ssl
      storage_adapter = @doc.at_xpath('//hawkular_agent:storage-adapter', 'hawkular_agent' => @hawkular_agent_ns)
      storage_adapter['use-ssl'] = 'true'
      storage_adapter['security-realm'] = 'UndertowRealm'
    end

    def sync
      File.write("#{@server_path}/standalone/configuration/standalone.xml", @doc.to_xml)
    end

    def security_realm_text_node(alias_name, keystore_password, key_password)
      "<security-realm name=\"UndertowRealm\">
          <server-identities>
            <ssl>
             <keystore path=\"hawkular.keystore\" relative-to=\"jboss.server.config.dir\""\
             " keystore-password=\"#{keystore_password}\" key-password=\"#{key_password}\" alias=\"#{alias_name}\" />
            </ssl>
          </server-identities>
        </security-realm>\n"
    end
  end
end
