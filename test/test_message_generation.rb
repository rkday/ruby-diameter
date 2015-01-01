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

describe 'creating an answer to a message' do
  before do
    @req = Message.new(command_code: 100, app_id: 106, avps: [AVP.create("User-Name", "shibboleth")])
  end
  
  it 'shares the same Command-Code and Application ID' do
    ans = @req.create_answer(2001)
    ans.command_code.must_equal 100
    ans.app_id.must_equal 106
  end

  it 'copies the requested AVPs' do
    ans = @req.create_answer(2001, copying_avps: ["User-Name"])
    ans['User-Name'].octet_string.must_equal "shibboleth"
  end
end
