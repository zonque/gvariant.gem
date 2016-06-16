# GVariant
[![Build Status](https://travis-ci.org/zonque/gvariant.gem.svg?branch=master)](https://travis-ci.org/zonque/gvariant.gem)

## Introduction

GVariant is a Ruby implementation for reading binary data and demarshal them into native Ruby data tyes using a GVariant type string.

For more information about the binary format implemented by this gem, please refer to the
[canonical documentation](https://people.gnome.org/~desrt/gvariant-serialisation.pdf).

## Install

To install GVariant, add the following line to a project's Gemfile:

```ruby
gem 'gvariant'
```

or run the following command:

```shell
gem install gvariant
```

## Examples

```ruby
# returns 'abc'
GVariant.read('s', [ 0x61, 0x62, 0x63, 0x0 ])

# returns [ true, 42, 'abc' ]
GVariant.read('(bus)', [ 0x1, 0x0, 0x0, 0x0, 0x2a, 0x0, 0x0, 0x0, 0x61, 0x62, 0x63, 0x0 ])

# returns "abc\x00"
GVariant.write('s', 'abc')

# returns "\u0001\u0000\u0000\u0000*\u0000\u0000\u0000abc\u0000"
GVariant.write('(bus)', [ true, 42, 'abc' ])
```

For more examples, please have a look at the test suite included in this repository.

## Contributing

Contributions are very welcome! Please file [bug reports](https://github.com/zonque/gvariant.gem/issues)
and [pull requests](https://github.com/zonque/gvariant.gem/pulls).

## License

All code in this repository is licensed under the [GNU Lesser General Public License version 3](LGPLv3.md).