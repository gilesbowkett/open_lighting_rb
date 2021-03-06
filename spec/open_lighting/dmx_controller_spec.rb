require 'spec_helper'

module OpenLighting
  describe DmxController do
    describe '.initialize' do
      context 'given default values' do
        it 'uses default fps' do
          c = DmxController.new
          c.fps.should == 40
        end
        it 'uses default universe' do
          c = DmxController.new
          c.universe.should == 1
        end
        it 'uses default cmd' do
          c = DmxController.new(:universe => 2)
          c.cmd.should == "ola_streaming_client -u 2"
        end
      end

      context 'given updated values' do
        it 'updates fps value' do
          c = DmxController.new(:fps => 20)
          c.fps.should == 20
        end
      end
    end

    describe ".devices" do
      before(:each) do
        @controller = DmxController.new
      end

      context 'when adding devices' do
        context 'when :start_address is specified' do
          before(:each) do
            @controller << DmxDevice.new(:start_address => 1)
            @controller << DmxDevice.new(:start_address => 6)
          end

          it 'should return devices in the same order as added' do
            @controller.devices.count.should == 2
            @controller.devices.first.start_address.should == 1
            @controller.devices.last.start_address.should == 6
          end

          it 'should attach controller to devices' do
            @controller.devices.first.controller.should == @controller
            @controller.devices.last.controller.should == @controller
          end
        end

        context 'when :start_address is not specified' do
          before(:each) do
            options = {:capabilities => [:pan, :tilt]}
            @controller << DmxDevice.new(options)
            @controller << DmxDevice.new(options)
            @controller << DmxDevice.new(options)
          end

          it 'should add default :start_address' do
            @controller.devices.count.should == 3
            @controller.devices.first.start_address.should == 1
            @controller.devices.last.start_address.should == 5
          end
        end
      end
    end

    describe ".to_dmx" do
      before(:each) do
        @controller = DmxController.new
        @controller << DmxDevice.new(:start_address => 1, :capabilities => [:pan, :tilt, :dimmer], :points => {:center => {:pan => 127, :tilt => 127}})
        @controller << DmxDevice.new(:start_address => 4, :capabilities => [:pan, :tilt, :dimmer], :points => {:center => {:pan => 127, :tilt => 127}})
      end

      it "should report correct capabilities" do
        @controller.capabilities.should == [:pan, :tilt, :dimmer]
      end

      it "should report correct points" do
        @controller.points.should == [:center]
      end

      it "should serialize all DmxDevices" do
        @controller.to_dmx.should == "0,0,0,0,0,0"
        @controller.buffer(:pan => 255)
        @controller.to_dmx.should == "255,0,0,255,0,0"
        @controller.buffer(:point => :center)
        @controller.to_dmx.should == "127,127,0,127,127,0"
      end

      it "should do method_missing magics" do
        @controller.to_dmx.should == "0,0,0,0,0,0"
        @controller.center
        @controller.to_dmx.should == "127,127,0,127,127,0"
        @controller.dimmer(80)
        @controller.to_dmx.should == "127,127,80,127,127,80"
        @controller.pan(25)
        @controller.to_dmx.should == "25,127,80,25,127,80"
        @controller.center
        @controller.to_dmx.should == "127,127,80,127,127,80"
      end

      it "should do method_missing magics" do
        @controller.connect_test_pipe
        @controller.center!
        @controller.read_pipe.gets.should == "127,127,0,127,127,0\n"
        @controller.dimmer!(80)
        @controller.read_pipe.gets.should == "127,127,80,127,127,80\n"
        @controller.close!
      end

      it "but not for incorrect names" do
        lambda { @controller.offcenter }.should raise_error NoMethodError
      end

      it "should honor overlapping start_address" do
        @controller << DmxDevice.new(:start_address => 5, :capabilities => [:pan, :tilt, :dimmer])
        @controller.buffer(:pan => 127)
        @controller.to_dmx.should == "127,0,0,127,127,0,0"
      end

      it "should insert zeros for missing data points" do
        @controller << DmxDevice.new(:start_address => 9, :capabilities => [:pan, :tilt, :dimmer])
        @controller.buffer(:pan => 127)
        @controller.to_dmx.should == "127,0,0,127,0,0,0,0,127,0,0"
      end
    end

    describe ".instant!" do
      before(:each) do
        @controller = DmxController.new(:test => true)
        @controller << DmxDevice.new(:start_address => 1, :capabilities => [:pan, :tilt, :dimmer])
        @controller << DmxDevice.new(:start_address => 4, :capabilities => [:pan, :tilt, :dimmer])
      end

      it "should write to the pipe" do
        @controller.instant!(:pan => 127)
        @controller.read_pipe.gets.should == "127,0,0,127,0,0\n"
        @controller.write_pipe.close
      end
    end

    describe ".ticks" do
      before(:each) do
        @controller = DmxController.new(:fps => 0.1)
      end

      it "should always have at least 1 tick" do
        @controller.ticks(1).should == 1
        @controller.ticks(-1).should == 1
        @controller.ticks(-100000).should == 1
        @controller.ticks(0).should == 1
      end

      it "should round down to fewer ticks" do
        @controller.ticks(25).should == 2
        @controller.ticks(30).should == 3
        @controller.ticks(35).should == 3
      end
    end

    describe ".interpolate" do
      context "with fps equal to one" do
        before(:each) do
          @controller = DmxController.new
        end

        it "should handle one step" do
          @controller.interpolate([1,1,1], [2,2,2], 1, 1).should == [2,2,2]
        end

        it "should handle multiple steps" do
          @controller.interpolate([1,1,1], [2,2,2], 2, 1).should == [1.5,1.5,1.5]
          @controller.interpolate([1,1,1], [2,2,2], 2, 2).should == [2,2,2]
        end

        it "should handle fractional input" do
          @controller.interpolate([1.5,1.5,1.5], [4.5,4.5,4.5], 2, 1).should == [3.0,3.0,3.0]
          @controller.interpolate([1.5,1.5,1.5], [4.5,4.5,4.5], 2, 2).should == [4.5,4.5,4.5]
        end
      end
    end

    describe ".begin_animation!" do
      before(:each) do
        @controller = DmxController.new(:fps => 1, :test => true)
        @controller << DmxDevice.new(:start_address => 1, :capabilities => [:pan, :tilt, :dimmer])
        @controller << DmxDevice.new(:start_address => 4, :capabilities => [:pan, :tilt, :dimmer])
      end

      it "should write interpolated values to the pipe" do
        @controller.animate!(:seconds => 5, :pan => 25)
        @controller.read_pipe.gets.should == "5,0,0,5,0,0\n"
        @controller.read_pipe.gets.should == "10,0,0,10,0,0\n"
        @controller.read_pipe.gets.should == "15,0,0,15,0,0\n"
        @controller.read_pipe.gets.should == "20,0,0,20,0,0\n"
        @controller.read_pipe.gets.should == "25,0,0,25,0,0\n"
        @controller.write_pipe.close
      end

      it "should allow block syntax" do
        @controller.begin_animation!(:seconds => 5) do |devices|
          devices[0].pan(25)
          devices[1].pan(50)
        end
        @controller.read_pipe.gets.should == "5,0,0,10,0,0\n"
        @controller.read_pipe.gets.should == "10,0,0,20,0,0\n"
        @controller.read_pipe.gets.should == "15,0,0,30,0,0\n"
        @controller.read_pipe.gets.should == "20,0,0,40,0,0\n"
        @controller.read_pipe.gets.should == "25,0,0,50,0,0\n"
        @controller.write_pipe.close
      end

      it "should allow sequential calls to method_missing and animate" do
        @controller.dimmer(50)
        @controller.to_dmx.should == "0,0,50,0,0,50"
        @controller.animate!(:seconds => 1, :dimmer => 127)
        @controller.read_pipe.gets.should == "0,0,127,0,0,127\n"
      end
    end
  end
end
