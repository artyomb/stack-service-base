module ToolRegistry
  class ExecutionContext
    include RpcErrorHelpers
  end

  class Definition
    attr_reader :name

    def initialize(name)
      @name = name.to_s
      @inputs = {}
    end

    def description(text = nil)
      return @description if text.nil?
      @description = text
    end

    def input(fields = {})
      @inputs.merge!(fields.transform_keys(&:to_s))
    end

    def input_schema
      properties = {}
      required = []

      @inputs.each do |field, config|
        cfg = config.transform_keys { |key| key.is_a?(Symbol) ? key : key.to_sym }
        required << field if cfg.delete(:required)
        properties[field] = cfg.transform_keys(&:to_s)
      end

      { type: "object", properties: properties, required: required }
    end

    def execute(&block) = @executor = block

    def to_h
      {
        name: name,
        description: description,
        inputSchema: input_schema
      }
    end

    def call(arguments)
      raise JsonRpcError.new(code: 500, message: "Tool #{name} missing executor") unless @executor

      ExecutionContext.new.instance_exec(symbolize_keys(arguments || {}), &@executor)
    end

    private

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end
  end

  module_function

  def define(name, &block)
    definition = Definition.new(name)
    definition.instance_eval(&block)
    registry[definition.name] = definition
  end

  def registry
    @registry ||= {}
  end

  def list
    registry.values.map(&:to_h)
  end

  def fetch(name)
    registry[name.to_s]
  end
end

def Tool(name, &block)
  ToolRegistry.define(name, &block)
end
