module Borjomi
  module Messages
    module Fountain
      module IncreasePressure
        struct Request
          include Bloom::Message

          property id : String
          property over_time : Int32
          property slope : Float64
          property intensity : Float64

          def initialize(@id : String, @over_time : Int32, @slope : Float32, @intensity : Float64)
          end
        end

        struct Response
          include Bloom::Message

          property id : String
          property pressure : Float64

          def initialize(@id : String, @pressure : Float64)
          end
        end
      end
    end
  end
end