class Payment < ActiveRecord::Base
  attr_accessible :profile
  validates_presence_of :profile
end
