# frozen_string_literal: true

module Kernel
  private

  def ENV! = ENV.method(:fetch)
end
