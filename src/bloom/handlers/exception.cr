module Bloom
  module Handlers
    class Exception
      Log = ::Log.for(self)

      include HTTP::Handler

      def call(context : HTTP::Server::Context)
        call_next(context)
      rescue exception
        call_exception(context, exception)
      end

      private def call_exception(context : HTTP::Server::Context, exception : ::Exception)
        return context if context.response.closed?

        case exception
        when Exceptions::BadRequest
          context.response.status_code = 400
        when Exceptions::NotFound
          context.response.status_code = 404
        when Exceptions::MethodNotAllowed
          context.response.status_code = 405
        when Exceptions::MissingField
          context.response.status_code = 422
        end

        context.response.headers.merge!({"Content-Type" => "application/json"})
        context.response.print({"success" => false, "message" => exception.message, "body" => nil}.to_json)

        context
      end
    end
  end
end
