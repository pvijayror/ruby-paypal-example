#require File.dirname(__FILE__) + '/../../config/environment.rb'
APP_CONFIG = YAML.load_file("#{Rails.root}/config/paypal.yml")[Rails.env]