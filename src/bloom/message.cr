module Bloom
  module Message
    annotation Field
    end

    annotation Options
    end

    macro included
      macro finished
        # Define a `new` directly in the included type,
        # so it overloads well with other possible initializes

        def self.new(buf : ::Protobuf::Buffer)
          new_from_buf(buf)
        end

        private def self.new_from_buf(buf : ::Protobuf::Buffer)
          instance = allocate
          instance.initialize(__pull_for_buf: buf)
          GC.add_finalizer(instance) if instance.responds_to?(:finalize)
          instance
        end

        def self.new(pull : ::JSON::PullParser)
          new_from_json_pull_parser(pull)
        end

        private def self.new_from_json_pull_parser(pull : ::JSON::PullParser)
          instance = allocate
          instance.initialize(__pull_for_json_serializable: pull)
          GC.add_finalizer(instance) if instance.responds_to?(:finalize)
          instance
        end

        {% if !@type.abstract? %}
          build_helpers
        {% end %}
      end
    end

    macro contract_of(syntax, &blk)
      FIELDS = {} of Int32 => HashLiteral(Symbol, ASTNode)
      {{yield}}
      _generate_decoder {{syntax}}
      _generate_encoder {{syntax}}
      _generate_hash_getters
    end

    macro contract(&blk)
      contract_of "proto2" {{blk}}
    end

    macro _add_field(tag, name, pb_type, options = {} of Symbol => Bool)
      {%
        t = ::Protobuf::PB_TYPE_MAP[pb_type] || pb_type
        FIELDS[tag] = {
          name:         name,
          pb_type:      pb_type,
          crystal_type: t,
          cast_type:    options[:repeated] ? "Array(#{t})?".id : options[:optional] ? "#{t}?".id : t.id,
          native:       !!::Protobuf::PB_TYPE_MAP[pb_type],
          optional:     !!options[:optional] || !!options[:repeated],
          repeated:     !!options[:repeated],
          default:      options[:default],
          packed:       !!options[:packed],
        }
      %}
    end

    macro optional(name, type, tag, default = nil, repeated = false, packed = false)
      _add_field({{tag.id}}, {{name}}, {{type}}, {optional: true, default: {{default}}, repeated: {{repeated}}, packed: {{packed}}})
    end

    macro required(name, type, tag, default = nil)
      _add_field({{tag.id}}, {{name}}, {{type}}, {default: {{default}}})
    end

    macro repeated(name, type, tag, packed = false)
      optional({{name}}, {{type}}, {{tag}}, nil, true, {{packed}})
    end

    macro extensions(range)
      # puts "extensions: {{range.id}}"
    end

    macro _generate_decoder(pbVer)
      def self.from_protobuf(io)
        new(::Protobuf::Buffer.new(io))
      end

      def initialize(*, __pull_for_buf buf : ::Protobuf::Buffer)
        {% for tag, field in FIELDS %}
          %var{tag} = nil
          %found{tag} = false
        {% end %}
        loop do
          tag_id, wire = buf.read_info
          case tag_id
          {% for tag, field in FIELDS %}
          when {{tag}}
            %found{tag} = true
            {%
              pb_type = ::Protobuf::PB_TYPE_MAP[field[:pb_type]]
              reader = !!pb_type ? "buf.read_#{field[:pb_type].id}" : "#{field[:crystal_type]}.new(buf)"
            %}
            {% if field[:repeated] %}\
              %var{tag} ||= [] of {{field[:crystal_type]}}
              {% if (pbVer != "proto2" && pb_type && ![String, Slice(UInt8)].includes?(pb_type.resolve)) || field[:packed] %}
                packed_buf_{{tag}} = buf.new_from_length.not_nil!
                loop do
                  %packed_var{tag} = {{(!!pb_type ? "packed_buf_#{tag}.read_#{field[:pb_type].id}" : "#{field[:crystal_type]}.new(packed_buf_#{tag})").id}}
                  break if %packed_var{tag}.nil?
                  %var{tag} << %packed_var{tag}
                end
              {% else %}
                {% if !field[:native] %}
                  if wire == 2
                    %embed_buf{tag} = buf.new_from_length.not_nil!
                    %value{tag} = {{field[:crystal_type]}}.new(%embed_buf{tag})
                  else
                    %value{tag} = {{reader.id}}
                  end
                {% else %}
                  %value{tag} = {{reader.id}}
                {% end %}
                break if %value{tag}.nil?
                %var{tag} << %value{tag}
              {% end %}
            {% else %}\
              {% if !field[:native] %}
                if wire == 2
                  %embed_buf{tag} = buf.new_from_length.not_nil!
                  %value{tag} = {{field[:crystal_type]}}.new(%embed_buf{tag})
                else
                  %value{tag} = {{reader.id}}
                end
              {% else %}
                %value{tag} = {{reader.id}}
              {% end %}
              break if %value{tag}.nil?
              %var{tag} = %value{tag}
            {% end %}\
          {% end %}
          when nil
            break
          else
            buf.skip(wire)
            next
          end
        end

        {% for tag, field in FIELDS %}
          {% if field[:optional] %}
            {% if field[:default] != nil %}
              @{{field[:name].id}} = %found{tag} ? (%var{tag}).as({{field[:cast_type]}}) : {{field[:default]}}
            {% else %}
              @{{field[:name].id}} = (%var{tag}).as({{field[:cast_type]}})
            {% end %}
          {% elsif field[:default] != nil %}
            @{{field[:name].id}} = %var{tag}.is_a?(Nil) ? {{field[:default]}} : (%var{tag}).as({{field[:cast_type]}})
          {% else %}
            @{{field[:name].id}} = (%var{tag}).as({{field[:cast_type]}})
          {% end %}
        {% end %}
      end

      def initialize(*,
        {% for tag, field in FIELDS %}
          {% unless field[:optional] %}
            @{{field[:name].id}} : {{field[:cast_type].id}},
          {% end %}
        {% end %}
        {% for tag, field in FIELDS %}
          {% if field[:optional] %}
            @{{field[:name].id}} : {{field[:cast_type].id}} = {{field[:default]}}{% unless field[:default] == nil %}.as({{field[:crystal_type]}}){% end %},
          {% end %}
        {% end %}
      )
      end
    end

    macro _generate_encoder(pbVer)
      def to_protobuf
        io = IO::Memory.new
        to_protobuf(io)
        io.rewind
      end

      def to_protobuf(io : IO, embedded = false)
        buf = ::Protobuf::Buffer.new(io)
        {% for tag, field in FIELDS %}
          %val{tag} = @{{field[:name].id}}
          %is_enum{tag} = %val{tag}.is_a?(Enum) || %val{tag}.is_a?(Array) && %val{tag}.first?.is_a?(Enum)
          %wire{tag} = ::Protobuf::WIRE_TYPES.fetch({{field[:pb_type]}}, %is_enum{tag} ? 0 : 2)
          {%
            pb_type = ::Protobuf::PB_TYPE_MAP[field[:pb_type]]
            writer = !!pb_type ? "buf.write_#{field[:pb_type].id}(@#{field[:name].id}.not_nil!)" : "buf.write_message(@#{field[:name].id}.not_nil!)"
          %}
          {% if field[:optional] %}
            if !@{{field[:name].id}}.nil?
              {% if field[:repeated] %}
                {% if (pbVer != "proto2" && pb_type && ![String, Slice(UInt8)].includes?(pb_type.resolve)) || field[:packed] %}
                  buf.write_info({{tag}}, 2)
                  buf.write_packed(@{{field[:name].id}}, {{field[:pb_type]}})
                {% else %}
                  @{{field[:name].id}}.not_nil!.each do |item|
                    buf.write_info({{tag}}, %wire{tag})
                    {%
                      writer = !!pb_type ? "buf.write_#{field[:pb_type].id}(item)" : "buf.write_message(item)"
                    %}
                    {{writer.id}}
                  end
                {% end %}
              {% else %}
                buf.write_info({{tag}}, %wire{tag})
                {{writer.id}}
              {% end %}
            end
          {% else %}
            buf.write_info({{tag}}, %wire{tag})
            {{writer.id}}
          {% end %}
        {% end %}
        io
      end
    end

    macro _generate_hash_getters
      def [](key : String)
        {% for tag, field in FIELDS %}
          return self.{{field[:name].id}} if {{field[:name].id.stringify}} == key
        {% end %}

        raise ::Protobuf::Error.new("Field not found: `#{key}`")
      end
    end

    def ==(other : ::Protobuf::Message)
      self.class == other.class &&
        to_protobuf.to_slice == other.to_protobuf.to_slice
    end

    def initialize(*, __pull_for_json_serializable pull : ::JSON::PullParser)
      {% begin %}
          {% properties = {} of Nil => Nil %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(::JSON::Field) %}
            {% unless ann && (ann[:ignore] || ann[:ignore_deserialize]) %}
              {%
                properties[ivar.id] = {
                  key:         ((ann && ann[:key]) || ivar).id.stringify.camelcase(lower: true),
                  has_default: ivar.has_default_value?,
                  default:     ivar.default_value,
                  nilable:     ivar.type.nilable?,
                  type:        ivar.type,
                  root:        ann && ann[:root],
                  converter:   ann && ann[:converter],
                  presence:    ann && ann[:presence],
                }
              %}
            {% end %}
          {% end %}

          # `%var`'s type must be exact to avoid type inference issues with
          # recursively defined serializable types
          {% for name, value in properties %}
            %var{name} = uninitialized ::Union({{value[:type]}})
            %found{name} = false
          {% end %}

          %location = pull.location
          begin
            pull.read_begin_object
          rescue exc : ::JSON::ParseException
            raise ::JSON::SerializableError.new(exc.message, self.class.to_s, nil, *%location, exc)
          end
          until pull.kind.end_object?
            %key_location = pull.location
            key = pull.read_object_key
            case key
            {% for name, value in properties %}
              when {{value[:key]}}
                begin
                  {% if value[:has_default] || value[:nilable] || value[:root] %}
                    if pull.read_null?
                      {% if value[:nilable] %}
                        %var{name} = nil
                        %found{name} = true
                      {% end %}
                      next
                    end
                  {% end %}

                  %var{name} =
                    {% if value[:root] %} pull.on_key!({{value[:root]}}) do {% else %} begin {% end %}
                      {% if value[:converter] %}
                        {{value[:converter]}}.from_json(pull)
                      {% else %}
                        ::Union({{value[:type]}}).new(pull)
                      {% end %}
                    end
                  %found{name} = true
                rescue exc : ::JSON::ParseException
                  raise ::JSON::SerializableError.new(exc.message, self.class.to_s, {{value[:key]}}, *%key_location, exc)
                end
            {% end %}
            else
              on_unknown_json_attribute(pull, key, %key_location)
            end
          end
          pull.read_next

          {% for name, value in properties %}
            if %found{name}
              @{{name}} = %var{name}
            else
              {% unless value[:has_default] || value[:nilable] %}
                raise ::JSON::SerializableError.new("Missing JSON attribute: {{value[:key].id}}", self.class.to_s, nil, *%location, nil)
              {% end %}
            end

            {% if value[:presence] %}
              @{{name}}_present = %found{name}
            {% end %}
          {% end %}
        {% end %}
      after_initialize
    end

    protected def after_initialize
    end

    protected def on_unknown_json_attribute(pull, key, key_location)
      pull.skip
    end

    protected def on_to_json(json : ::JSON::Builder)
    end

    def to_json(json : ::JSON::Builder)
      {% begin %}
          {% options = @type.annotation(Options) %}
          {% emit_nulls = options && options[:emit_nulls] %}

          {% properties = {} of Nil => Nil %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(::JSON::Field) %}
            {% unless ann && (ann[:ignore] || ann[:ignore_serialize] == true) %}
              {%
                properties[ivar.id] = {
                  key:              ((ann && ann[:key]) || ivar).id.stringify.camelcase(lower: true),
                  root:             ann && ann[:root],
                  converter:        ann && ann[:converter],
                  emit_null:        (ann && (ann[:emit_null] != nil) ? ann[:emit_null] : emit_nulls),
                  ignore_serialize: ann && ann[:ignore_serialize],
                }
              %}
            {% end %}
          {% end %}

          json.object do
            {% for name, value in properties %}
              _{{name}} = @{{name}}

              {% if value[:ignore_serialize] %}
                unless {{ value[:ignore_serialize] }}
              {% end %}

                {% unless value[:emit_null] %}
                  unless _{{name}}.nil?
                {% end %}

                  json.field({{value[:key]}}) do
                    {% if value[:root] %}
                      {% if value[:emit_null] %}
                        if _{{name}}.nil?
                          nil.to_json(json)
                        else
                      {% end %}

                      json.object do
                        json.field({{value[:root]}}) do
                    {% end %}

                    {% if value[:converter] %}
                      if _{{name}}
                        {{ value[:converter] }}.to_json(_{{name}}, json)
                      else
                        nil.to_json(json)
                      end
                    {% else %}
                      _{{name}}.to_json(json)
                    {% end %}

                    {% if value[:root] %}
                      {% if value[:emit_null] %}
                        end
                      {% end %}
                        end
                      end
                    {% end %}
                  end

                {% unless value[:emit_null] %}
                  end
                {% end %}
              {% if value[:ignore_serialize] %}
                end
              {% end %}
            {% end %}
            on_to_json(json)
          end
        {% end %}
    end

    module Strict
      protected def on_unknown_json_attribute(pull, key, key_location)
        raise ::JSON::SerializableError.new("Unknown JSON attribute: #{key}", self.class.to_s, nil, *key_location, nil)
      end
    end

    module Unmapped
      @[Field(ignore: true)]
      property json_unmapped = Hash(String, JSON::Any).new

      protected def on_unknown_json_attribute(pull, key, key_location)
        json_unmapped[key] = begin
          JSON::Any.new(pull)
        rescue exc : ::JSON::ParseException
          raise ::JSON::SerializableError.new(exc.message, self.class.to_s, key, *key_location, exc)
        end
      end

      protected def on_to_json(json)
        json_unmapped.each do |key, value|
          json.field(key) { value.to_json(json) }
        end
      end
    end

    macro use_json_discriminator(field, mapping)
      {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
        {% mapping.raise "Mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
      {% end %}

      def self.new(pull : ::JSON::PullParser)
        location = pull.location

        discriminator_value = nil

        # Try to find the discriminator while also getting the raw
        # string value of the parsed JSON, so then we can pass it
        # to the final type.
        json = String.build do |io|
          JSON.build(io) do |builder|
            builder.start_object
            pull.read_object do |key|
              if key == {{field.id.stringify}}.camelcase(lower: true)
                value_kind = pull.kind
                case value_kind
                when .string?
                  discriminator_value = pull.string_value
                when .int?
                  discriminator_value = pull.int_value
                when .bool?
                  discriminator_value = pull.bool_value
                else
                  raise ::JSON::SerializableError.new("JSON discriminator field '{{field.id}}' has an invalid value type of #{value_kind.to_s}", to_s, nil, *location, nil)
                end
                builder.field(key, discriminator_value)
                pull.read_next
              else
                builder.field(key) { pull.read_raw(builder) }
              end
            end
            builder.end_object
          end
        end

        unless discriminator_value
          raise ::JSON::SerializableError.new("Missing JSON discriminator field '{{field.id}}'", to_s, nil, *location, nil)
        end

        case discriminator_value
        {% for key, value in mapping %}
          {% if mapping.is_a?(NamedTupleLiteral) %}
            when {{key.id.stringify}}.camelcase(lower: true)
          {% else %}
            {% if key.is_a?(StringLiteral) %}
              when {{key}}
            {% elsif key.is_a?(NumberLiteral) || key.is_a?(BoolLiteral) %}
              when {{key.id}}
            {% elsif key.is_a?(Path) %}
              when {{key.resolve}}
            {% else %}
              {% key.raise "Mapping keys must be one of StringLiteral, NumberLiteral, BoolLiteral, or Path, not #{key.class_name.id}" %}
            {% end %}
          {% end %}
          {{value.id}}.from_json(json)
        {% end %}
        else
          raise ::JSON::SerializableError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", to_s, nil, *location, nil)
        end
      end
    end

    class SerializableError < JSON::ParseException
      getter klass : String
      getter attribute : String?

      def initialize(message : String?, @klass : String, @attribute : String?, line_number : Int32, column_number : Int32, cause)
        message = String.build do |io|
          io << message
          io << "\n  parsing "
          io << klass
          if attribute = @attribute
            io << '#' << attribute
          end
        end
        super(message, line_number, column_number, cause)
        if cause
          @line_number, @column_number = cause.location
        end
      end
    end

    macro build_helpers
      # contract_of "proto3" do
      #   optional :name, :string, 1
      # end

      contract_of "proto3" do
        {% for method in @type.methods %}
          {% if method.visibility == :public && !method.name.stringify.includes?("=") && !Bloom::Constants::RESERVED_METHODS.includes?(method.name.stringify) %}

            {% name = method.name.stringify.camelcase(lower: true) %}
            {% type = method.return_type.stringify.gsub(/ \| ::Nil/, "?") %}

            {%
              current_type =
                if type == "String" || type == "String?"
                  {true, "string"}
                elsif type == "Int32" || type == "Int32?"
                  {true, "int32"}
                elsif type == "Int64" || type == "Int64?"
                  {true, "int64"}
                elsif type == "Float64" || type == "Float64?"
                  {true, "double"}
                elsif type == "Float32" || type == "Float32?"
                  {true, "float"}
                elsif type == "UInt32" || type == "UInt32?"
                  {true, "uint32"}
                elsif type == "UInt64" || type == "UInt64?"
                  {true, "uint64"}
                elsif type == "Bool" || type == "Bool?"
                  {true, "bool"}
                else
                  {false, method.return_type.resolve}
                end
            %}

            {% unless type.includes?("?") %}
              {% if current_type.first %}
                required :{{ method.name.stringify.id }}, :{{ current_type.last.id }}, {{ @type.methods.map(&.name.stringify) }}.reject(&.includes?("=")).index({{ method.name.stringify }}).not_nil! + 1
              {% else %}
                required :{{ method.name.stringify.id }}, {{ current_type.last.id }}, {{ @type.methods.map(&.name.stringify) }}.reject(&.includes?("=")).index({{ method.name.stringify }}).not_nil! + 1
              {% end %}
            {% else %}
              {% if current_type.first %}
                optional :{{ method.name.stringify.id }}, :{{ current_type.last.id }}, {{ @type.methods.map(&.name.stringify) }}.reject(&.includes?("=")).index({{ method.name.stringify }}).not_nil! + 1
              {% else %}
                optional :{{ method.name.stringify.id }}, :{{ current_type.last.id }}, {{ @type.methods.map(&.name.stringify) }}.reject(&.includes?("=")).index({{ method.name.stringify }}).not_nil! + 1
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      end
    end
  end
end
