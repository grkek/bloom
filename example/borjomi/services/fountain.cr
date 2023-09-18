require "../messages/**"

module Borjomi
  module Services
    struct Fountain
      include Bloom::Service

      alias IncreasePressure = Messages::Fountain::IncreasePressure

      def increase_pressure(request : IncreasePressure::Request) : IncreasePressure::Response
        pressure = (request.over_time * request.slope) ** request.intensity
        IncreasePressure::Response.new(id: request.id, pressure: pressure)
      end
    end
  end
end