require "../src/bloom"
require "./borjomi/**"


module Borjomi
end

Log.setup(:debug)

package = Borjomi::Package.new

package.services.push(Borjomi::Services::Fountain.new)
package.services.push(Borjomi::Services::Gate.new)

server = Bloom::Server.new(package)

server.router.insert(0, Bloom::Handlers::Log.new)

server.run
