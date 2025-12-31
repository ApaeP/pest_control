# frozen_string_literal: true

module PestControl
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
