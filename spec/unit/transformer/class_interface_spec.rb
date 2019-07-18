# frozen_string_literal: true

require 'ostruct'
require 'dry/equalizer'

describe Transproc::Transformer do
  let(:container) { Module.new { extend Transproc::Registry } }
  let(:klass) { Transproc::Transformer[container] }
  let(:transformer) { klass.new }

  describe '.import' do
    it 'allows importing functions into an auto-configured registry' do
      klass = Class.new(Transproc::Transformer) do
        import Transproc::ArrayTransformations
        import Transproc::Coercions

        define! do
          map_array(&:to_symbol)
        end
      end

      transformer = klass.new

      expect(transformer.(['foo', 'bar'])).to eql([:foo, :bar])
    end
  end

  describe '.new' do
    it 'supports arguments' do
      klass = Class.new(Transproc::Transformer) do
        import Transproc::ArrayTransformations
        import Transproc::Coercions

        define! do
          map_array(&:to_symbol)
        end

        def initialize(good)
          @good = good
        end

        def good?
          @good
        end
      end

      transformer = klass.new(true)

      expect(transformer).to be_good
    end
  end

  describe '.container' do
    it 'returns the configured container' do
      expect(klass.container).to be(container)
    end

    context 'with setter argument' do
      let(:container) { double(:custom_container) }

      it 'sets and returns the container' do
        klass.container(container)

        expect(klass.container).to be(container)
      end
    end
  end

  describe 'inheritance' do
    let(:container) do
      Module.new do
        extend Transproc::Registry

        def self.arbitrary(value, fn)
          fn[value]
        end
      end
    end

    let(:superclass) do
      Class.new(Transproc::Transformer[container]) do
        arbitrary ->(v) { v + 1 }
      end
    end

    let(:subclass) do
      Class.new(superclass) do
        arbitrary ->(v) { v * 2 }
      end
    end

    it 'inherits container from superclass' do
      expect(subclass.container).to be(superclass.container)
    end

    it 'inherits transproc from superclass' do
      expect(superclass.new.call(2)).to be(3)
      expect(subclass.new.call(2)).to be(6)
    end
  end

  describe '.[]' do
    subject(:subclass) { klass[another_container] }

    let(:another_container) { double('Transproc') }

    it 'sets a container' do
      expect(subclass.container).to be(another_container)
    end

    it 'returns a class' do
      expect(subclass).to be_a(Class)
    end

    it 'creates a subclass of Transformer' do
      expect(subclass).to be < Transproc::Transformer
    end

    it 'does not change super class' do
      expect(klass.container).to be(container)
    end

    it 'does not inherit transproc' do
      expect(klass[container].new.transproc).to be_nil
    end

    context 'with predefined transformer' do
      let(:klass) do
        Class.new(Transproc::Transformer[container]) do
          container.import Transproc::Coercions
          container.import Transproc::HashTransformations

          map_value :attr, t(:to_symbol)
        end
      end

      it "inherits parent's transproc" do
        expect(klass[container].new.transproc).to eql(klass.new.transproc)
      end
    end
  end

  describe '.define' do
    let(:container) do
      Module.new do
        extend Transproc::Registry

        import Transproc::HashTransformations

        def self.to_symbol(v)
          v.to_sym
        end
      end
    end

    let(:klass) { Transproc::Transformer[container] }

    it 'defines anonymous transproc' do
      transproc = klass.define do
        map_value(:attr, t(:to_symbol))
      end

      expect(transproc[attr: 'abc']).to eq(attr: :abc)
    end

    it 'has .build alias' do
      transproc = klass.build do
        map_value(:attr, t(:to_symbol))
      end

      expect(transproc[attr: 'abc']).to eq(attr: :abc)
    end

    it 'does not affect original transformer' do
      klass.define do
        map_value(:attr, :to_sym.to_proc)
      end

      expect(klass.new.transproc).to be_nil
    end

    context 'with custom container' do
      let(:container) do
        Module.new do
          extend Transproc::Registry

          def self.arbitrary(value, fn)
            fn[value]
          end
        end
      end

      let(:klass) { described_class[container] }

      it 'uses a container from the transformer' do
        transproc = klass.define! do
          arbitrary ->(v) { v + 1 }
        end.new

        expect(transproc.call(2)).to eq 3
      end
    end

    context 'with predefined transformer' do
      let(:klass) do
        Class.new(described_class[container]) do
          define! do
            map_value :attr, ->(v) { v + 1 }
          end
        end
      end

      it 'builds transformation from the DSL definition' do
        transproc = klass.new

        expect(transproc.call(attr: 2)).to eql(attr: 3)
      end
    end
  end

  describe '.t' do
    subject(:klass) { Transproc::Transformer[container] }

    let(:container) do
      Module.new do
        extend Transproc::Registry

        import Transproc::HashTransformations
        import Transproc::Conditional

        def self.custom(value, suffix)
          value + suffix
        end
      end
    end

    it 'returns a registed function' do
      expect(klass.t(:custom, '_bar')).to eql(container[:custom, '_bar'])
    end

    it 'is useful in DSL' do
      transproc = Class.new(klass) do
        map_value :a, t(:custom, '_bar')
      end.new

      expect(transproc.call(a: 'foo')).to eq(a: 'foo_bar')
    end

    it 'works in nested block' do
      transproc = Class.new(klass) do
        map_values do
          is String, t(:custom, '_bar')
        end
      end.new

      expect(transproc.call(a: 'foo', b: :symbol)).to eq(a: 'foo_bar', b: :symbol)
    end
  end

  describe '.method_missing' do
    it 'responds to missing when there is a corresponding function' do
      container.import Transproc::HashTransformations

      expect(klass.method(:map_values)).to be_a(Method)
    end

    it 'raises when there is no corresponding function or instance method' do
      expect { klass.not_here }.to raise_error(NoMethodError, /not_here/)
    end
  end

  describe '#call' do
    let(:container) do
      Module.new do
        extend Transproc::Registry

        import Transproc::HashTransformations
        import Transproc::ArrayTransformations
        import Transproc::ClassTransformations
      end
    end

    let(:klass) do
      Class.new(Transproc::Transformer[container]) do
        map_array do
          symbolize_keys
          rename_keys user_name: :name
          nest :address, [:city, :street, :zipcode]

          map_value :address do
            constructor_inject Test::Address
          end

          constructor_inject Test::User
        end
      end
    end

    let(:input) do
      [
        { 'user_name' => 'Jane',
          'city' => 'NYC',
          'street' => 'Street 1',
          'zipcode' => '123'
        }
      ]
    end

    let(:expected_output) do
      [
        Test::User.new(
          name: 'Jane',
          address: Test::Address.new(
            city: 'NYC',
            street: 'Street 1',
            zipcode: '123'
          )
        )
      ]
    end

    before do
      module Test
        class User < OpenStruct
          include Dry::Equalizer(:name, :address)
        end

        class Address < OpenStruct
          include Dry::Equalizer(:city, :street, :zipcode)
        end
      end
    end

    it "transforms input" do
      expect(transformer.(input)).to eql(expected_output)
    end

    context 'with custom registry' do
      let(:klass) do
        Class.new(Transproc::Transformer[registry]) do
          append ' is awesome'
        end
      end

      let(:registry) do
        Module.new do
          extend Transproc::Registry

          def self.append(value, suffix)
            value + suffix
          end
        end
      end

      it 'uses custom functions' do
        expect(transformer.('transproc')).to eql('transproc is awesome')
      end
    end
  end
end
