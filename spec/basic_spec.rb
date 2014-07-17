ENV['RACK_ENV'] = 'test'

require_relative '../main'
require 'test_helper'

describe 'Git TODO Blamer' do
  it "can load the homepage" do
    get '/'
    expect(last_response).to be_ok
  end
  it "can load the all by age page" do
    get '/age'
    expect(last_response).to be_ok
  end
  it "can load the core repo" do
    get '/repo/core'
    expect(last_response).to be_ok
  end
  it "can load by email" do
    get '/email/tristan.rice@socrata.com'
    expect(last_response).to be_ok
  end
end
