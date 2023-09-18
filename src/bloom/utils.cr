module Bloom
  module Utils
    def self.to_protobuf_type(type : String) : Tuple(Bool, String)
      case type
      when "String", "String?"
        return {true, "string"}
      when "Int32", "Int32?"
        return {true, "int32"}
      when "Int64", "Int64?"
        return {true, "int64"}
      when "Float64", "Float64?"
        return {true, "double"}
      when "Float32", "Float32?"
        return {true, "float"}
      when "UInt32", "UInt32?"
        return {true, "uint32"}
      when "UInt64", "UInt64?"
        return {true, "uint64"}
      when "Bool", "Bool?"
        return {true, "bool"}
      else
        if type.size != 0
          return {false, type}
        else
          raise Exception.new("An issue occured with the type converter, unsupported type: #{type}")
        end
      end
    end
  end
end
