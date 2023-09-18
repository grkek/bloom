module Bloom
  module Handlers
    class Twirp
      Log = ::Log.for(self)

      include HTTP::Handler

      @services = Hash(String, Service).new

      def initialize(@prefix = "/twirp")
      end

      def add_service(service : Service)
        service_name = name(service.name)
        @services[service_name] = service

        Log.debug { "Added #{service_name} to the services" }
      end

      def add_service(services : Array(Service))
        services.each do |service|
          service_name = name(service.name)
          @services[service_name] = service

          Log.debug { "Added #{service_name} to the services" }
        end
      end

      def call(context : HTTP::Server::Context)
        raise Exceptions::MethodNotAllowed.new("Method not allowed") if context.request.method != "POST"

        content_type = context.request.headers["Content-Type"]

        if body = context.request.body
          *prefixes, service_name, method_name = context.request.path.split("/")
          raise Exceptions::BadRequest.new("Invalid prefix") if prefixes.join("/") != @prefix

          if service = @services[service_name]
            return_value = service.handle_method(method_name, body, content_type: content_type)

            context.response.headers.merge!({"Content-Type" => content_type})

            return return_value.to_protobuf(context.response.output) if content_type == "application/protobuf"
            return {"success" => true, "message" => nil, "body" => return_value}.to_json(context.response.output) if content_type == "application/json"

            raise Exceptions::BadRequest.new("Unsupported Content-Type header was provided")
          else
            raise Exceptions::NotFound.new("Service not found")
          end
        end
      end

      private def name(service_name : String) : String
        crumbs = service_name.split(".")
        package = crumbs.shift.downcase

        [package].concat(crumbs).join(".")
      end
    end
  end
end
