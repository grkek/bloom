module Borjomi
  module Messages
    module Gate
      module CloseLock
        struct Request
          include Bloom::Message

          property id : String

          def initialize(@id : String)
          end
        end

        struct Response
          include Bloom::Message

          property id : String

          @[Bloom::Message::Field(key: "lockState")]
          property lock_state : Int32

          def initialize(@id : String, lock_state : Enums::LockState)
            @lock_state = lock_state.to_i32
          end
        end
      end
    end
  end
end