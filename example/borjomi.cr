require "../src/bloom"
require "./borjomi/**"


module Borjomi
end

Log.setup(:debug)

package = Borjomi::Package.new
package.services.push(Borjomi::Services::Fountain.new)

server = Bloom::Server.new(package)
server.run
