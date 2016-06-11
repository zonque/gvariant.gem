class GVariantBasicType
  attr_reader :id, :fixed_size, :default_value, :alignment

  def initialize(id, pack_format, alignment, fixed_size, default_value)
    @id, @pack_format, @alignment, @fixed_size, @default_value =
      id, pack_format, alignment, fixed_size, default_value
  end

  def align(i)
    (i + @alignment - 1) & ~(@alignment - 1)
  end

  def pad(buf)
    l = buf.length
    (align(l) - l).times do
      buf.concat(0)
    end
  end

  def read(buf)
    return @default_value if @fixed_size && buf.length != @fixed_size
    buf.unpack(@pack_format).first
  end

  def write(value)
    [value || @default_value].pack(@pack_format)
  end
end

class GVariantByteType < GVariantBasicType
  def initialize
    super('y', 'C', 1, 1, 0)
  end
end

class GVariantSignedShortType < GVariantBasicType
  def initialize
    super('n', 's', 2, 2, 0)
  end
end

class GVariantUnsignedShortType < GVariantBasicType
  def initialize
    super('q', 'S', 2, 2, 0)
  end
end

class GVariantSignedIntType < GVariantBasicType
  def initialize
    super('i', 'l', 4, 4, 0)
  end
end

class GVariantUnsignedIntType < GVariantBasicType
  def initialize
    super('u', 'L', 4, 4, 0)
  end
end

class GVariantSignedLongType < GVariantBasicType
  def initialize
    super('x', 'q', 8, 8, 0)
  end
end

class GVariantUnsignedLongType < GVariantBasicType
  def initialize
    super('t', 'Q', 8, 8, 0)
  end
end

class GVariantDoubleType < GVariantBasicType
  def initialize
    super('d', 'd', 8, 8, 0.0)
  end
end

class GVariantBooleanType < GVariantBasicType
  def initialize
    super('b', 'C', 1, 1, false)
  end

  def read(buf)
    b = super(buf)
    b != false && b != 0
  end

  def write(value)
    super((value != 0 && value != false && value != nil) ? 1: 0)
  end
end

class GVariantStringType < GVariantBasicType
  def initialize(id)
    super(id, 'Z*', 1, nil, '')
  end

  def read(buf)
    return @default_value if (buf.length == 0 || buf[buf.length - 1] != "\x00")
    buf.unpack("Z*").first
  end
end

class GVariantMaybeType < GVariantBasicType
  def initialize(id, maybe_element)
    super(id, nil, maybe_element.alignment, nil, nil)
    @element = maybe_element
  end

  def read(buf)
    l = buf.length

    # Nothing
    return nil if l == 0

    # Just
    if (@element.fixed_size)
      return nil if l != @element.fixed_size
      @element.read(buf)
    else
      @element.read(buf[0..l - 1])
    end
  end

  def write(val)
    if val
      buf = @element.write(val)
      buf.concat(0) unless @element.fixed_size
      buf
    else
      ""
    end
  end
end

class GVariantVariantType < GVariantBasicType
  def initialize
    super('v', nil, 8, nil, { type: '()', value: {} })
  end

  def read(buf)
    value, sep, type = buf[0..buf.length - 1].rpartition("\x00")
    { type: type, value: GVariant.read(type, value) }
  end

  def write(variant)
    buf = GVariant.write(variant[:type], variant[:value])
    buf.concat(0)
    buf << variant[:type]
  end
end

class GVariantOffsetType < GVariantBasicType

  def initialize(id, alignment, default_value)
    @offset_size = nil
    super(id, nil, alignment, nil, default_value)
  end

  def read_offset(buf, n)
    l = buf.length
    determine_offset_type(l)
    buf.unpack("@#{l + @offset_size * n}#{@offset_pack_format}")[0]
  end

  def write_offsets(buf, offsets)
    return buf if offsets.empty?
    offset_size_prev = nil
    packed_size = 0
    packed = ""

    loop do
      determine_offset_type(buf.length + packed_size)
      break if @offset_size == offset_size_prev
      offset_size_prev = @offset_size

      packed_size = offsets.count * @offset_size
      packed = offsets.pack("#{@offset_pack_format}*")
    end

    buf << packed
  end

  private

  def determine_offset_type(l)
    if @offset_size.nil?
      if (l < 0xff)
        @offset_size = 1
        @offset_pack_format = 'C'
      elsif (l <= 0xffff)
        @offset_size = 2
        @offset_pack_format = 'S'
      elsif (l < 0xffffffff)
        @offset_size = 4
        @offset_pack_format = 'L'
      else
        raise ArgumentError.new("Offset range too big.")
      end
    end
  end

end

class GVariantDictionaryType < GVariantOffsetType
  def initialize(id, key_element, value_element)
    super(id, [ key_element.alignment, value_element.alignment ].max,
          [ key_element.default_value, value_element.default_value ])

    @key_element = key_element
    @value_element = value_element

    if key_element.fixed_size && value_element.fixed_size
      @fixed_size = value_element.align(key_element.fixed_size) + value_element.fixed_size
    end
  end

  def read(buf)
    return @default_value if @fixed_size && buf.length != @fixed_size

    if @key_element.fixed_size
      key_end = @key_element.fixed_size
      value_end = buf.length
    else
      key_end = read_offset(buf, -1)
      value_end = buf.length - @offset_size
    end

    key = @key_element.read(buf[0..key_end - 1]).to_sym
    value = @value_element.read(buf[@value_element.align(key_end)..value_end - 1])

    Hash[key, value]
  end

  def write(vals)
    buf = ""
    offsets = []

    vals.each_pair do |key, value|
      @key_element.pad(buf)
      buf << @key_element.write(key.to_s)
      unless @key_element.fixed_size
        offsets << buf.length
      end

      @value_element.pad(buf)
      buf << @value_element.write(value)
      unless @value_element.fixed_size || key == vals.keys.last
        offsets << buf.length
      end
    end

    write_offsets(buf, offsets)
    buf
  end
end

class GVariantArrayType < GVariantOffsetType
  def initialize(id, array_element)
    super(id, array_element.alignment, [])
    @element = array_element
  end

  def read(buf)
    size = buf.length

    if size == 0
      return @element.is_a?(GVariantDictionaryType) ? {} : @default_value
    end

    values = []
    c = 0

    if (@element.fixed_size)
      return [] if (size % @element.fixed_size != 0)
      n = size / @element.fixed_size

      n.times do
        values << @element.read(buf[c, @element.fixed_size])
        c += @element.fixed_size
      end
    else
      n = (size - read_offset(buf, -1)) / @offset_size

      n.times do |i|
        o = read_offset(buf, -n + i)
        values << @element.read(buf[c..o - 1])
        c = @element.align(o)
      end
    end

    values
  end

  def write(vals)
    buf = ""
    offsets = []

    vals.each do |val|
      v = @element.write(val)
      @element.pad(buf)
      buf << v
      offsets << buf.length
    end

    write_offsets(buf, offsets) unless @element.fixed_size
    buf
  end
end

class GVariantTupleType < GVariantOffsetType
  def initialize(id, elements)
    super(id, 1, [])
    @elements = elements
    @fixed_size = 0

    elements.each do |element|
      if element.fixed_size
        unless @fixed_size.nil?
          @fixed_size = element.align(@fixed_size + element.fixed_size)
        end
      else
        @fixed_size = nil
      end

      if element.alignment > @alignment
        @alignment = element.alignment
      end

      @default_value << element.default_value
    end

    @fixed_size = 1 if @fixed_size == 0

    if @fixed_size
      @fixed_size = align(@fixed_size)
    end
  end

  def read(buf)
    return @default_value if @fixed_size && buf.length != @fixed_size

    cur_offset = 0
    c = 0

    @elements.map do |element|
      c = element.align(c)

      if element.fixed_size
        n = c + element.fixed_size
      elsif element != @elements.last
        cur_offset -= 1
        n = read_offset(buf, cur_offset)
      else
        read_offset(buf, 0)
        n = buf.length - @offset_size * -cur_offset
      end

      v = element.read(buf[c..n - 1])
      c = n
      v
    end
  end

  def write(vals)
    buf = ""
    offsets = []
    o = 0
    i = 0

    @elements.each do |element|
      b = element.write(vals[i])
      element.pad(buf)
      buf << b
      i += 1

      o += b.length
      offsets << o unless element.fixed_size || element == @elements.last
    end

    pad(buf)
    write_offsets(buf, offsets)
    buf
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
      raise ArgumentError.new("Invalid type string") unless maybe_element
      GVariantMaybeType.new(signature[index, maybe_element.id.length + 1], maybe_element)
    when 'a'
      array_element = next_type(signature, index + 1)
      raise ArgumentError.new("Invalid type string") unless array_element
      GVariantArrayType.new(signature[index, array_element.id.length + 1], array_element)
    when '{'
      key_element = next_type(signature, index + 1)
      value_element = next_type(signature, index + 1 + key_element.id.length)
      raise ArgumentError.new("Invalid type string") unless key_element && value_element
      GVariantDictionaryType.new(signature[index, key_element.id.length + value_element.id.length + 2], key_element, value_element)
    when '('
      sig_end = index + 1
      elements = []

      while signature[sig_end] != ')' do
        e = next_type(signature, sig_end)
        sig_end += e.id.length
        elements << e
      end

      GVariantTupleType.new(signature[index..sig_end], elements)
    end
  end

  def self.parse_type(str)
    type = next_type(str, 0)

    if type.nil? || type.id.length != str.length
      raise ArgumentError.new("Invalid type string: #{str}")
    end

    type
  end

  def self.read(typestr, buf)
    buf = buf.pack("C*") if buf.is_a? Array
    buf.freeze if RUBY_VERSION >= '2.1.0'
    type = parse_type(typestr)
    type.read(buf)
  end

  def self.write(typestr, value)
    type = parse_type(typestr)
    type.write(value)
  end
end