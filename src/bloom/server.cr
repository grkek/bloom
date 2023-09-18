module Bloom
  class Server
    property router : Array(HTTP::Handler) = [Handlers::Exception.new] of HTTP::Handler

    def initialize(package : Package)
      twirp = Handlers::Twirp.new

      package.services.each do |service|
        twirp.add_service service
      end

      @router.push(twirp)
    end

    def host : String
      "0.0.0.0"
    end

    def port : Int32
      8118
    end

    def reuse_port : Bool
      false
    end

    def server : HTTP::Server
      HTTP::Server.new(@router)
    end

    def key_file : String
      ENV["KEY"]? || ""
    end

    def cert_file : String
      ENV["CERTIFICATE"]? || ""
    end

    {% unless flag?(:ssl) %}
      def ssl : Bool
        false
      end
    {% else %}
      def ssl : OpenSSL::SSL::Context::Server
        context = OpenSSL::SSL::Context::Server.new

        context
          .private_key = key_file

        context
          .certificate_chain = cert_file

        context
      end
    {% end %}

    protected def schema : String
      ssl ? "https" : "http"
    end

    def run
      server = self.server

      unless server.each_address { |_| break true }
        {% if flag?(:ssl) %}
          if ssl
            server.bind_tls(host, port, ssl, reuse_port)
          else
            server.bind_tcp(host, port, reuse_port)
          end
        {% else %}
          server.bind_tcp(host, port, reuse_port)
        {% end %}
      end

      Log.info { "Listening at #{schema}://#{host}:#{port}" }

      Process.on_interrupt { exit }
      server.listen
    end
  end
end
