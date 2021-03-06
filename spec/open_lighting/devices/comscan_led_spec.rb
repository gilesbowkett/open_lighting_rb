require 'spec_helper'

module OpenLighting
  module Devices
    describe ComscanLed do
      before(:each) do
        @device = ComscanLed.new
      end

      context ".initialize" do
        context "without arguments" do
          it "should know gobo wheel points" do
            @device.point(:red).should == {:gobo => 15}
          end
        end
      end
    end
  end
end
