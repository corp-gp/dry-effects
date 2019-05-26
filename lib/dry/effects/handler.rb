require 'fiber'
require 'dry/effects/effect'

module Dry
  module Effects
    class Handler
      def self.[](effect = Undefined, as:, **kwargs)
        if Undefined.equal?(effect)
          type, identifier = kwargs.to_a.first
        else
          type, identifier = effect, Undefined
        end

        handler = new(type, identifier)

        Module.new do
          define_method(as) { |*args, &block| handler.(*args, &block) }
        end
      end

      BREAK = Object.new.freeze

      attr_reader :providers, :effect_type, :identifier

      def initialize(effect_type, identifier = Undefined, providers: Effects.providers)
        @providers = providers
        @effect_type = effect_type
        @identifier = identifier
      end

      def call(*args)
        provider = providers[effect_type].new(*args, identifier: identifier)
        fiber = ::Fiber.new { yield }

        result = fiber.resume

        fiber_result = loop do
          break result unless fiber.alive?

          if result.is_a?(Effect) && handle?(provider, result)
            instruction = provider.public_send(result.name, *result.payload)

            if BREAK.equal?(instruction)
              break result
            else
              result = fiber.resume(instruction)
            end
          else
            result = fiber.resume(Effects.yield(result))
          end
        end

        provider.output(fiber_result)
      end

      def handle?(provider, effect)
        effect.type.equal?(effect_type) && effect.identifier.equal?(provider.identifier)
      end
    end
  end
end
