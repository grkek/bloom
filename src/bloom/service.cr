module Bloom
  module Service
    Log = ::Log.for(self)

    macro included
      macro finished
        {% if !@type.abstract? %}
          build_helpers
        {% end %}
      end
    end

    macro build_helpers
      property name : String = {{ @type.name.stringify }}.gsub(/::/, ".")

      def handle_method(method_name : String, body : IO, content_type : String)
        begin
          case method_name.underscore
            {% for method in @type.methods %}
            when {{method.name.stringify}}
              case content_type
              when "application/json"
                Log.debug { "Casting into #{{{method.args.first.restriction.stringify}}} and executing #{method_name.underscore} using JSON parser" }
                return {{method.name.id}}({{method.args.first.restriction}}.from_json(body))
              when "application/protobuf"
                Log.debug { "Casting into #{{{method.args.first.restriction.stringify}}} and executing #{method_name.underscore} using Protobuf parser" }
                return {{method.name.id}}({{method.args.first.restriction}}.from_protobuf(body))
              else
                raise Bloom::Exceptions::BadRequest.new("Content Type #{content_type} is not supported")
              end
            {% end %}
            else
              raise Bloom::Exceptions::NotFound.new("Method #{method_name} was not found")
          end
        rescue exception : JSON::ParseException
          message = exception.message || "One or more fields are missing, or your provided JSON data is invalid"
          raise Bloom::Exceptions::MissingField.new(message.split("\n").first)
        end
      end
    end
  end
end
