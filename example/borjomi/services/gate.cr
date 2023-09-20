require "../messages/**"

module Borjomi
  module Services
    struct Gate
      include Bloom::Service

      alias OpenLock = Messages::Gate::OpenLock
      alias CloseLock = Messages::Gate::CloseLock

      alias LockState = Enums::LockState

      def open_lock(request : OpenLock::Request) : OpenLock::Response
        OpenLock::Response.new(id: request.id, lock_state: LockState::OFF)
      end

      def close_lock(request : OpenLock::Request) : CloseLock::Response
        CloseLock::Response.new(id: request.id, lock_state: LockState::ON)
      end
    end
  end
end