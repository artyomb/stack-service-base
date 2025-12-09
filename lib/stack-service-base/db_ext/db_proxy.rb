class Sequel::Dataset
  def self.===(obj) = obj.is_a?(DProxy) || super
end

class DProxy
  def initialize(dataset, model, path = [], &block)
    @model, @dataset, @final, @path = model, dataset, block, path
  end

  def indent(str) = puts "\t" * @path.size + str
  def method_missing(name, *args, **kwargs, &block)
    all_args = [*args, **kwargs, block:].reject(&:nil?)
    # indent "DProxy::#{@model} #{name}(#{all_args}) => IN" unless QUIET

    response = if @final && name.to_sym == :all
       @final.call self, *all_args
     else
       @dataset.send(name, *args, **kwargs, &block)
     end
    # indent "DProxy::#{@model} #{name}(#{all_args}) OUT => #{response.inspect}" unless QUIET
    wrap?(response) ? self.class.new(response, @model, @path + [name => all_args, prev: self], &@final) : response
  end

  def wrap?(r) = r.is_a?(Sequel::Dataset::PlaceholderLiteralizer) || r.is_a?(Sequel::Dataset)

  def respond_to_missing?(method_name, include_private = false)
    @dataset.respond_to?(method_name, include_private)
  end

  alias_method :_clone, :clone

  def clone( *args, **kwargs, &block)
    method_missing(:clone, *args, **kwargs, &block)
  end
end


