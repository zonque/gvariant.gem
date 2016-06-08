require 'minitest/autorun'
require 'gvariant'

class GVariantTest < Minitest::Test

  def gvariant_compare(typestr, data, exp)
    assert_equal(exp, GVariant.read(typestr, data))
  end

  def test_basic
    assert GVariant.new(nil, nil) != nil
  end

  def test_invalid_type
    assert_raises ArgumentError do GVariant.read('bb', []) end
    assert_raises ArgumentError do GVariant.read('', [])   end
    assert_raises ArgumentError do GVariant.read('ä', [])  end
    assert_raises ArgumentError do GVariant.read('(a', []) end
  end

  def test_boolean
    assert_equal(false, GVariant.read('b', [ 0x00 ]))
    assert_equal(true,  GVariant.read('b', [ 0x01 ]))
  end

  def test_numbers
    assert_equal(  42, GVariant.read('y', [ 0x2a ]))

    assert_equal( -42, GVariant.read('n', [ 0xd6, 0xff ]))
    assert_equal(  42, GVariant.read('q', [ 0x2a, 0x00 ]))

    assert_equal( -42, GVariant.read('i', [ 0xd6, 0xff, 0xff, 0xff ]))
    assert_equal(  42, GVariant.read('u', [ 0x2a, 0x00, 0x00, 0x00 ]))

    assert_equal( -42, GVariant.read('x', [ 0xd6, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(  42, GVariant.read('t', [ 0x2a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ]))
  end

  def test_large_integers
    [ 'x', 't' ].each do |t|
      assert_equal(                96, GVariant.read(t, [ 0x60, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0 ]))
      assert_equal(              3072, GVariant.read(t, [ 0x0, 0xc, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0 ]))
      assert_equal(             98304, GVariant.read(t, [ 0x0, 0x80, 0x1, 0x0, 0x0, 0x0, 0x0, 0x0 ]))
      assert_equal(           3145728, GVariant.read(t, [ 0x0, 0x0, 0x30, 0x0, 0x0, 0x0, 0x0, 0x0 ]))
      assert_equal(         100663296, GVariant.read(t, [ 0x0, 0x0, 0x0, 0x6, 0x0, 0x0, 0x0, 0x0 ]))
      assert_equal(        3221225472, GVariant.read(t, [ 0x0, 0x0, 0x0, 0xc0, 0x0, 0x0, 0x0, 0x0 ]))
      assert_equal(      103079215104, GVariant.read(t, [ 0x0, 0x0, 0x0, 0x0, 0x18, 0x0, 0x0, 0x0 ]))
      assert_equal(     3298534883328, GVariant.read(t, [ 0x0, 0x0, 0x0, 0x0, 0x0, 0x3, 0x0, 0x0 ]))
      assert_equal(   105553116266496, GVariant.read(t, [ 0x0, 0x0, 0x0, 0x0, 0x0, 0x60, 0x0, 0x0 ]))
      assert_equal(  3377699720527872, GVariant.read(t, [ 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xc, 0x0 ]))
    end

    assert_equal(                 -96, GVariant.read('x', [ 0xa0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(               -3072, GVariant.read('x', [ 0x0, 0xf4, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(              -98304, GVariant.read('x', [ 0x0, 0x80, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(            -3145728, GVariant.read('x', [ 0x0, 0x0, 0xd0, 0xff, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(          -100663296, GVariant.read('x', [ 0x0, 0x0, 0x0, 0xfa, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(         -3221225472, GVariant.read('x', [ 0x0, 0x0, 0x0, 0x40, 0xff, 0xff, 0xff, 0xff ]))
    assert_equal(       -103079215104, GVariant.read('x', [ 0x0, 0x0, 0x0, 0x0, 0xe8, 0xff, 0xff, 0xff ]))
    assert_equal(      -3298534883328, GVariant.read('x', [ 0x0, 0x0, 0x0, 0x0, 0x0, 0xfd, 0xff, 0xff ]))
    assert_equal(    -105553116266496, GVariant.read('x', [ 0x0, 0x0, 0x0, 0x0, 0x0, 0xa0, 0xff, 0xff ]))
    assert_equal(   -3377699720527872, GVariant.read('x', [ 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xf4, 0xff ]))
  end

  def test_doubles
    gvariant_compare('d', [ 0x0, 0x0, 0x0, 0x0, 0x0, 0x40, 0x45, 0x40 ], 42.5)
  end

  def test_strings
    assert_equal('',    GVariant.read('s', [ 0x00 ]))
    assert_equal('abc', GVariant.read('s', [ 0x61, 0x62, 0x63, 0x0 ]))
  end

  def test_variants
    assert_equal({ type: 'i', value: 42 },      GVariant.read('v', [ 0x2a, 0x0, 0x0, 0x0, 0x0, 0x69 ]))
    assert_equal({ type: 'ay', value: [ 42 ] }, GVariant.read('v', [ 0x2a, 0x0, 0x61, 0x79 ]))
  end

  def test_maybes
    assert_equal(nil,   GVariant.read('my', []))
    assert_equal(42,    GVariant.read('my', [ 0x2a ]))
    assert_equal('abc', GVariant.read('ms', [ 0x61, 0x62, 0x63, 0x0, 0x0 ]))
  end

  def test_arrays
    assert_equal([],                   GVariant.read('ay', []))
    assert_equal([ 1, 2, 3 ],          GVariant.read('ay', [ 0x1, 0x2, 0x3 ]))
    assert_equal([],                   GVariant.read('as', []))
    assert_equal([ 'abc', 'x', 'yz' ], GVariant.read('as', [ 0x61, 0x62, 0x63, 0x0, 0x78, 0x0, 0x79, 0x7a, 0x0, 0x4, 0x6, 0x9 ]))
  end

  def test_tuples
    assert_equal([],                  GVariant.read('()', []))
    assert_equal([ true, 42, 'abc' ], GVariant.read('(bus)', [ 0x1, 0x0, 0x0, 0x0, 0x2a, 0x0, 0x0, 0x0, 0x61, 0x62, 0x63, 0x0 ]))
    assert_equal([ true, 'abc', 42 ], GVariant.read('(bsy)', [ 0x1, 0x61, 0x62, 0x63, 0x0, 0x2a, 0x5 ]))
  end

  def test_dicts
    assert_equal({}, GVariant.read('a{sv}', []))
    assert_equal([{ abc: { type: 'i', value: 42 }}, { def: { type: 'i', value: 43 }}],
                 GVariant.read('a{sv}', [ 0x61, 0x62, 0x63, 0x0, 0x0, 0x0, 0x0, 0x0, 0x2a, 0x0, 0x0, 0x0, 0x0, 0x69, 0x4, 0x0,
                                                 0x64, 0x65, 0x66, 0x0, 0x0, 0x0, 0x0, 0x0, 0x2b, 0x0, 0x0, 0x0, 0x0, 0x69, 0x4, 0xf, 0x1f ]))
  end

  def test_malformed
    assert_equal(false, GVariant.read('b', [ 0x1, 0x1, 0x1 ]))
    assert_equal(0,     GVariant.read('y', []))
    assert_equal(0,     GVariant.read('u', [ 0x00, 0x01 ]))
    assert_equal(0,     GVariant.read('x', [ 0x0, 0x1, 0x2, 0x3 ]))

    assert_equal(true,  GVariant.read('b', [ 0x2a ]))
    assert_equal('',    GVariant.read('s', [ 0x61 ]))
    assert_equal('a',   GVariant.read('s', [ 0x61, 0x0, 0x61, 0x0  ]))

    assert_equal(nil, GVariant.read('my', []))
    assert_equal(nil, GVariant.read('mu', [ 0x1, 0x2, 0x3, 0x4, 0x5]))
    assert_equal([],  GVariant.read('aq', [ 0x1 ]))
  end

  def test_spec
    assert_equal([ 0, 1, 2, 3 ], GVariant.read('aq', [ 0x00, 0x00, 0x1, 0x00, 0x2, 0x00, 0x3, 0x00 ]))
    assert_equal([ "hello", "world" ], GVariant.read('as', [ 104, 101, 108, 108, 111, 0, 119, 111, 114, 108, 100, 0, 0x06, 0x0c ]))

    # Examples from chapter 2.6 of the specification
    assert_equal('hello world', GVariant.read('s',  [ 104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 0 ]))
    assert_equal('hello world', GVariant.read('ms', [ 104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 0, 0 ]))
    assert_equal([ true, false, false, true, true ], GVariant.read('ab', [ 1, 0, 0, 1, 1 ]))
    assert_equal([ 'foo', -1 ], GVariant.read('(si)', [ 102, 111, 111, 0, 0xff, 0xff, 0xff, 0xff, 0x04 ]))
    assert_equal([ [ 'hi', -2 ], [ 'bye', -1 ] ], GVariant.read('a(si)',
                 [ 104, 105, 0, 0, 0xfe, 0xff, 0xff, 0xff, 3, 0, 0, 0, 98, 121, 101, 0, 0xff, 0xff, 0xff, 0xff, 4, 9, 0x15 ]))
    assert_equal([ 'i', 'can', 'has', 'strings?' ], GVariant.read('as',
                 [ 105, 0, 99, 97, 110, 0, 104, 97, 115, 0, 115, 116, 114, 105, 110, 103, 115, 63, 0, 0x02, 0x06, 0x0a, 0x13 ]))

    assert_equal([ [105, 'can'], ['has', 'strings?'] ], GVariant.read('((ys)as)',
                   [ 105, 99, 97, 110, 0, 104, 97, 115, 0, 115, 116, 114, 105, 110, 103, 115, 63, 0, 0x04, 0x0d, 0x05 ]))

    assert_equal([ 0x70, 0x80 ], GVariant.read('(yy)', [ 0x70, 0x80 ]))
    assert_equal([ 96, 0x70 ],   GVariant.read('(iy)', [ 0x60, 0, 0, 0, 0x70, 0, 0, 0 ]))
    assert_equal([ [ 96, 0x70 ], [ 648, 0xf7 ] ], GVariant.read('a(iy)', [ 0x60, 0, 0, 0, 0x70, 0, 0, 0, 0x88, 0x02, 0x00, 0x00, 0xf7, 0, 0, 0 ]))
    assert_equal([ 0x04, 0x05, 0x06, 0x07 ], GVariant.read('ay', [ 0x04, 0x05, 0x06, 0x07 ]))
    assert_equal([ 4, 258 ], GVariant.read('ai', [ 0x04, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00 ]))
    assert_equal({ 'a key': 514 }, GVariant.read('{si}', [ 97, 32, 107, 101, 121, 0, 0x00, 0x00, 0x02, 0x02, 0x00, 0x00, 0x06 ]))
  end

end