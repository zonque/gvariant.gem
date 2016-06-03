require 'awesome_print'
require 'pry'

class GVariantBasicType
  attr_reader :id, :fixed_size, :default_value
  attr_accessor :alignment

  def align(i)
    i += @alignment - 1
    i &= ~(@alignment - 1)
    i
  end

  def read(buf, s, e)
    if @fixed_size and (e - s) != @fixed_size
      @default_value
    else
      buf.unpack("@#{s}#{@unpack}")[0]
    end
  end
end

class GVariantByteType < GVariantBasicType
  def initialize
    @id = 'y'
    @alignment = 1
    @fixed_size = 1
    @unpack = 'C'
    @default_value = 0
  end
end

class GVariantSignedShortType < GVariantBasicType
  def initialize
    @id = 'n'
    @alignment = 2
    @fixed_size = 2
    @unpack = 's'
    @default_value = 0
  end
end

class GVariantUnsignedShortType < GVariantBasicType
  def initialize
    @id = 'q'
    @alignment = 2
    @fixed_size = 2
    @unpack = 'S'
    @default_value = 0
  end
end

class GVariantSignedIntType < GVariantBasicType
  def initialize
    @id = 'i'
    @alignment = 4
    @fixed_size = 4
    @unpack = 'l'
    @default_value = 0
  end
end

class GVariantUnsignedIntType < GVariantBasicType
  def initialize
    @id = 'u'
    @alignment = 4
    @fixed_size = 4
    @unpack = 'L'
    @default_value = 0
  end
end

class GVariantSignedLongType < GVariantBasicType
  def initialize
    @id = 'x'
    @alignment = 8
    @fixed_size = 8
    @unpack = 'q'
    @default_value = 0
  end
end

class GVariantUnsignedLongType < GVariantBasicType
  def initialize
    @id = 't'
    @alignment = 8
    @fixed_size = 8
    @unpack = 'Q'
    @default_value = 0
  end
end

class GVariantDoubleType < GVariantBasicType
  def initialize
    @id = 'd'
    @alignment = 8
    @fixed_size = 8
    @unpack = 'd'
    @default_value = 0.0
  end
end

class GVariantBooleanType < GVariantBasicType
  def initialize
    @id = 'b'
    @alignment = 1
    @fixed_size = 1
    @unpack = 'C'
    @default_value = false
  end

  def read(buf, s, e)
    b = super(buf, s, e)
    return b if b == false
    b != 0
  end
end

class GVariantStringType < GVariantBasicType
  def initialize(id)
    @id = id
    @alignment = 1
    @unpack = 'Z*'
    @fixed_size = nil
    @default_value = ''
  end

  def read(buf, s, e)
    return @default_value if (s == e || buf.unpack("@#{e-1}C")[0] != 0)
    buf.unpack("@#{s}Z*")[0]
  end
end

class GVariantMaybeType < GVariantBasicType
  def initialize(id, maybe_element)
    @id = id
    @alignment = maybe_element.alignment
    @element = maybe_element
    @default_value = nil
  end

  def read(buf, s, e)
    # Nothing
    return nil if (s == e)

    # Just
    if (@element.fixed_size)
      return nil if (e - s) != @element.fixed_size
      @element.read(buf, s, e)
    else
      @element.read(buf, s, e - 1)
    end
  end
end

class GVariantVariantType < GVariantBasicType
  def initialize
    @id = 'v'
    @alignment = 8
    @default_value = { type: '()', value: {} }
  end

  def read(buf, s, e)
    value, sep, type = buf[s..e-1].rpartition("\x00")
    { type: type, value: GVariant.deserialize(type, value) }
  end
end

class GVariantOffsetType < GVariantBasicType

  def prepare_offsets(s, e)
    return if (s == e)

    if (e - s < 0xff)
      @offset_size = 1
      @offset_unpack = 'C'
    elsif (e - s <= 0xffff)
      @offset_size = 2
      @offset_unpack = 'S'
    elsif (e - s < 0xffffffff)
      @offset_size = 4
      @offset_unpack = 'L'
    else
      raise ArgumentError
    end

    @offset_end = e
  end

  def get_offset(buf, n)
    buf.unpack("@#{@offset_end + @offset_size * n}#{@offset_unpack}")[0]
  end
end

class GVariantDictionaryType < GVariantOffsetType
  def initialize(id, key_element, value_element)
    @id = id
    @key_element = key_element
    @value_element = value_element
    @alignment = [ key_element.alignment, value_element.alignment ].max
    @default_value = [ key_element.default_value, value_element.default_value ]

    if key_element.fixed_size and value_element.fixed_size
      @fixed_size = value_element.align(key_element.fixed_size) + value_element.fixed_size
    else
      @fixed_size = nil
    end
  end

  def read(buf, s, e)
    return @default_value if @fixed_size and (e - s) != @fixed_size

    if @key_element.fixed_size
      key_end = s + @key_element.fixed_size
      value_end = e
    else
      prepare_offsets(s, e)
      key_end = s + get_offset(buf, -1)
      value_end = e - @offset_size
    end

    dict = {}
    dict[@key_element.read(buf, s, key_end).to_sym] = @value_element.read(buf, @value_element.align(key_end), value_end)
    dict
  end
end

class GVariantArrayType < GVariantOffsetType
  def initialize(id, array_element)
    @id = id
    @alignment = array_element.alignment
    @element = array_element
    @default_value = []
  end

  def read(buf, s, e)
    return @element.id[0] == '{' ? {} : [] if (s == e) # FIXME use is_a?

    values = []
    size = e - s

    if (@element.fixed_size)
      return [] if (size % @element.fixed_size != 0)

      (size / @element.fixed_size).times do
        values << @element.read(buf, s, s + @element.fixed_size)
        s += @element.fixed_size
      end
    else
      prepare_offsets(s, e)
      n = (e - get_offset(buf, -1)) / @offset_size
      c = s

      n.times do |i|
        o = get_offset(buf, -n + i)
        values << @element.read(buf, c, o)
        c = s + @element.align(o)
      end
    end

    values
  end
end

class GVariantTupleType < GVariantOffsetType
  def initialize(id, elements)
    @id = id
    @elements = elements
    @alignment = 1
    @fixed_size = 0
    @default_value = []

    @elements.each do |e|
      if e.fixed_size
        if @fixed_size != nil
          @fixed_size = e.align(@fixed_size) + e.fixed_size
        end
      else
        @fixed_size = nil
      end

      if e.alignment > @alignment
        @alignment = e.alignment
      end

      @default_value << e.default_value
    end

    @fixed_size = 1 if @fixed_size == 0
  end

  def read(buf, s, e)
    return @default_value if @fixed_size and (e - s) != @fixed_size

    prepare_offsets(s, e)
    cur_offset = 0
    c = s

    @elements.map do |element|
      c = element.align(c)

      if element.fixed_size
        n = c + element.fixed_size
      elsif element != @elements.last
        cur_offset -= 1
        n = get_offset(buf, cur_offset)
      else
        n = e - @offset_size * -cur_offset
      end

      v = element.read(buf, c, n)
      c = n
      v
    end
  end
end


class GVariant

  def initialize(typestr, buffer)
    @typestr, @buffer = typestr, buffer
  end

  def self.next_type(signature, index)

    case signature[index]
    when 'y'
      GVariantByteType.new
    when 'n'
      GVariantSignedShortType.new
    when 'q'
      GVariantUnsignedShortType.new
    when 'i'
      GVariantSignedIntType.new
    when 'u'
      GVariantUnsignedIntType.new
    when 'x'
      GVariantSignedLongType.new
    when 't'
      GVariantUnsignedLongType.new
    when 'd'
      GVariantDoubleType.new
    when 'b'
      GVariantBooleanType.new
    when 's', 'g', 'o'
      GVariantStringType.new(signature[index])
    when 'v'
      GVariantVariantType.new
    when 'm'
      maybe_element = next_type(signature, index + 1)
      GVariantMaybeType.new(signature.slice(index, maybe_element.id.length + 1), maybe_element)
    when 'a'
      array_element = next_type(signature, index + 1)
      GVariantArrayType.new(signature.slice(index, array_element.id.length + 1), array_element)
    when '{'
      key_element = next_type(signature, index + 1)
      value_element = next_type(signature, index + 1 + key_element.id.length)
      GVariantDictionaryType.new(signature.slice(index, key_element.id.length + value_element.id.length + 2), key_element, value_element)
    when '('
      x = index + 1
      elements = []

      while signature[x] != ')' do
        e = next_type(signature, x)
        x += e.id.length
        elements << e
      end

      GVariantTupleType.new(signature.slice(index, x + 1), elements)

#    else
#      binding.pry
    end
  end

  def self.parse_type(str)
    type = next_type(str, 0)
    raise ArgumentError if type.nil? or type.id.length != str.length
    type
  end

  def self.deserialize(typestr, buffer)
    buffer = buffer.pack("C*") if buffer.is_a? Array
    type = parse_type(typestr)
    type.read(buffer, 0, buffer.length)
  end

#  def self.deserialize(typestr, buffer)
#    new(type_str, data).deserialize
#  end

end