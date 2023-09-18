module Bloom
  module Package
    macro included
      macro finished
        {% if !@type.abstract? %}
          build_helpers
        {% end %}
      end
    end

    macro build_helpers
      property name : String = {{ @type.name.stringify }}.gsub(/::/, ".").split(".").first.downcase
      property services : Array(Bloom::Service) = [] of Bloom::Service
    end
  end
end
