require 'minitest_helper'
require 'diameter/message'

include Diameter

describe 'The Hop-by-Hop identifier of a message' do

  it 'is unique between requests' do
    msg1 = Message.new(command_code: 8, app_id: 0)
    msg2 = Message.new(command_code: 8, app_id: 0)
    msg1.hbh.wont_equal msg2.hbh
  end
end

describe 'The End-to-End identifier of a message' do

  it 'is unique between requests' do
    msg1 = Message.new(command_code: 8, app_id: 0)
    msg2 = Message.new(command_code: 8, app_id: 0)
    msg1.ete.wont_equal msg2.ete
  end
end

