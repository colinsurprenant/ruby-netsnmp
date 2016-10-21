module NETSNMP
  # Abstracts the PDU variable structure into a ruby object
  #
  class Varbind
    Error = Class.new(Error)

    attr_reader :oid, :value

    # @param [FFI::Pointer] pointer to the variable list
    def initialize(oid, value: nil)
      @oid = oid.is_a?(OID) ? oid : OID.new(oid)
      @value = value
    end


    def to_ber
      encoded = String.new
      encoded << @oid.to_ber
      encoded << BER.encode(@value)
      BER.encode_sequence(encoded)
    end
  end


  # Abstracts the Varbind used for the PDU Request
  class RequestVarbind < Varbind

    # @param [Symbol] symbol_type symbol representing the type
    # @return [Integer] the C net-snmp flag indicating the type
    # @raise [Error] when the symbol is unsupported
    #
    def convert_type(symbol_type)
      case symbol_type
        when :integer    then Core::Constants::ASN_INTEGER
        when :gauge      then Core::Constants::ASN_GAUGE
        when :counter    then Core::Constants::ASN_COUNTER
        when :timeticks  then Core::Constants::ASN_TIMETICKS
        when :unsigned   then Core::Constants::ASN_UNSIGNED
        when :boolean    then Core::Constants::ASN_BOOLEAN
        when :string     then Core::Constants::ASN_OCTET_STR
        when :binary     then Core::Constants::ASN_BIT_STR
        when :ip_address then Core::Constants::ASN_IPADDRESS
        else 
          raise Error, "#{symbol_type} cannot be converted"
      end
    end

    # @param [Object] value the value to convert
    # @param [Integer] type the C net-snmp level object type flakg
    #
    # @return [FFI::Pointer] pointer to the memory location where the value is stored
    #
    def convert_value(value, type)
      case type
        when Core::Constants::ASN_INTEGER,
             Core::Constants::ASN_GAUGE,
             Core::Constants::ASN_COUNTER,
             Core::Constants::ASN_TIMETICKS,
             Core::Constants::ASN_UNSIGNED
          new_val = FFI::MemoryPointer.new(:long)
          new_val.write_long(value)
          new_val
        when Core::Constants::ASN_OCTET_STR,
             Core::Constants::ASN_BIT_STR,
             Core::Constants::ASN_OPAQUE
          value
        when Core::Constants::ASN_IPADDRESS
            # TODO
        when Core::Constants::ASN_OBJECT_ID
          value.pointer
        when Core::Constants::ASN_NULL,
             Core::Constants::SNMP_NOSUCHOBJECT,
             Core::Constants::SNMP_NOSUCHINSTANCE,
             Core::Constants::SNMP_ENDOFMIBVIEW
            nil
        else
          raise Error, "Unknown variable type: #{type}" 
      end
    end
  end

  # Abstracts the Varbind used for the PDU Response
  # 
  class ResponseVarbind < Varbind

    attr_reader :value, :oid_code

    # @param [FFI::Pointer] pointer pointer to the response varbind structure
    # 
    # @note it loads the value and oid code on initialization
    #
    def initialize(encoded)
      oid, value = decode(encoded)
      super(oid, value)
    end

    private

    def decode(encoded)
    end

    # @return [Object] the value for the varbind (a ruby type, a string, an integer, a symbol etc...)
    #
    def load_varbind_value
      object_type = @struct[:type]
      case object_type
      when Core::Constants::ASN_OCTET_STR, 
           Core::Constants::ASN_OPAQUE
        @struct[:val][:string].read_string(@struct[:val_len])
      when Core::Constants::ASN_INTEGER
        @struct[:val][:integer].read_long
      when Core::Constants::ASN_UINTEGER, 
           Core::Constants::ASN_TIMETICKS,  
           Core::Constants::ASN_COUNTER, 
           Core::Constants::ASN_GAUGE
        @struct[:val][:integer].read_ulong
      when Core::Constants::ASN_IPADDRESS
        @struct[:val][:objid].read_string(@struct[:val_len]).unpack('CCCC').join(".")
      when Core::Constants::ASN_NULL
        nil
      when Core::Constants::ASN_OBJECT_ID
        OID.from_pointer(@struct[:val][:objid], @struct[:val_len] / OID.default_size)
      when Core::Constants::ASN_COUNTER64
        counter = Core::Structures::Counter64.new(@struct[:val][:counter64])
        counter[:high] * 2^32 + counter[:low]
      when Core::Constants::ASN_BIT_STR
        # XXX not sure what to do here.  Is this obsolete?
      when Core::Constants::SNMP_ENDOFMIBVIEW
        :endofmibview
      when Core::Constants::SNMP_NOSUCHOBJECT
        :nosuchobject
      when Core::Constants::SNMP_NOSUCHINSTANCE
        :nosuchinstance
      else
        raise Error, "#{object_type} is an invalid type"
      end
    end

  end
end
