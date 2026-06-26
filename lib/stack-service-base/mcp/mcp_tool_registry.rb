module ToolRegistry
  class ExecutionContext
    include RpcErrorHelpers
  end

  class Registry
    attr_reader :registry

    def initialize
      @registry = {}
    end

    def define(name, &block)
      definition = Definition.new(name)
      definition.instance_eval(&block)
      @registry[definition.name] = definition
    end

    def list
      registry.values.map(&:to_h)
    end

    def fetch(name)
      registry[name.to_s]
    end
  end

  class Definition
    attr_reader :name

    def initialize(name)
      @name = name.to_s
      @inputs = {}
      @annotations = {}
    end

    def description(text = nil)
      return @description if text.nil?
      @description = text
    end

    def input(fields = {})
      @inputs.merge!(fields.transform_keys(&:to_s))
    end

    def input_schema(schema = nil)
      return @input_schema || build_input_schema if schema.nil?

      @input_schema = stringify_keys(schema)
    end

    def annotations(value = nil)
      return @annotations if value.nil?

      @annotations = stringify_keys(value)
    end

    def call(&block) = @executor = block

    def to_h
      payload = {
        name: name,
        description: description,
        inputSchema: input_schema
      }
      payload[:annotations] = annotations unless annotations.empty?
      payload
    end

    def call_tool(arguments)
      raise JsonRpcError.new(code: -32603, message: "Tool #{name} missing executor") unless @executor

      ExecutionContext.new.instance_exec(symbolize_keys(arguments || {}), &@executor)
    end

    private

    def build_input_schema
      properties = {}
      required = []

      @inputs.each do |field, config|
        cfg = stringify_keys(config)
        required << field if cfg.delete('required')
        properties[field] = cfg
      end

      { type: 'object', properties: properties, required: required }
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), memo| memo[key.to_s] = stringify_keys(item) }
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end
  end

  module_function

  def default
    @default ||= Registry.new
  end

  def define(name, &block)
    default.define(name, &block)
  end

  def registry
    default.registry
  end

  def list
    default.list
  end

  def fetch(name)
    default.fetch(name)
  end
end

def Tool(name, &block)
  ToolRegistry.define(name, &block)
end
