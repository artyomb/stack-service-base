if defined? Async
  # require 'async'

  module Enumerable
    def map_async
      results = Array.new(self.size)
      self.each_with_index.map do |item, index|
        Async do
          results[index] = item.respond_to?(:to_ary) ? yield(*item.to_ary) : yield(item)
        end
      end.map(&:wait)
      results
    end
  end

  # Usage:
  #   async def foo(a,b,c)
  def async(name)
    original_method = self.respond_to?(:instance_method) ? instance_method(name) : method(name)
    self.respond_to?(:remove_method) ? remove_method(name) : Object.send(:remove_method, name)
    original_method = original_method.respond_to?(:unbind) ? original_method.unbind : original_method

    define_method(name) do |*args, **kwargs, &block|
      Async do
        original_method.bind(self).call(*args, **kwargs, &block)
      end
    end
  end
end