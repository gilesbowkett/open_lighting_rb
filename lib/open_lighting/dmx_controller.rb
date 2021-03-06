require 'json'

module OpenLighting
  # The DmxController class is responsible for sending control messages across
  # the DMX bus.
  #
  # Due to idiosynchricies of the underlying open_lighting subsytem, all devices
  # must receive a control signal each time anything on the bus receives a
  # control signal. The DmxController class is responsible for aggregating this
  # information from the DmxDevice instances and sending it down the bus.
  class DmxController
    attr_accessor :fps, :devices, :universe, :cmd, :read_pipe, :write_pipe, :do_not_sleep
    def initialize(options = {})
      @devices = []
      (options[:devices] || []).each {|dev| @devices << dev}
      self.fps = options[:fps] || 40
      self.universe = options[:universe] || 1
      self.cmd = options[:cmd] || "ola_streaming_client -u #{universe}"

      if options[:test]
        self.do_not_sleep = true
        self.connect_test_pipe
      end
    end

    def connect_test_pipe
      self.read_pipe, self.write_pipe = IO.pipe
    end

    def devices
      @devices
    end

    def <<(val)
      val.start_address ||= current_values.count + 1
      val.controller = self
      @devices << val
    end

    def set(options = {})
      warn "[DEPRECATION] `set` is deprecated. Use `buffer` instead."
    end

    def buffer(options = {})
      @devices.each {|device| device.buffer(options)}
    end

    def write!(values=current_values)
      self.write_pipe ||= IO.popen(self.cmd, "w")

      # DMX only wants integer inputs
      values.map!{|i| i.to_i}

      self.write_pipe.write "#{values.join ","}\n"
      self.write_pipe.flush
    end

    def close!
      self.write_pipe.close if self.write_pipe
      self.read_pipe.close  if self.read_pipe
    end

    def instant!(options = {})
      buffer(options)
      write!
    end

    def to_dmx
      # dmx addresses start at 1, ruby arrays start at zero
      current_values.join ","
    end

    def current_values
      results = []
      @devices.each do |d|
        results[d.start_address, d.start_address+d.capabilities.count] = d.current_values
      end
      # backfill unknown values with zero, in case of gaps due to starting_address errors
      results.map{|i| i.nil? ? 0 : i}.drop(1)
    end

    def ticks(seconds)
      [1, (seconds.to_f * self.fps.to_f).to_i].max
    end

    def wait_time
      1.0 / self.fps.to_f
    end

    def transition!(options = {}, &block)
      warn "[DEPRECATION] `transition!` is deprecated. Use `begin_animation!` instead."
    end

    def animate!(options = {}, &block)
      previous = current_values
      buffer(options)

      block.call(self) if block

      count = ticks(options[:seconds])
      count.times do |i|
        # interpolate previous to current
        write! interpolate(previous, current_values, count, i+1)
        sleep(wait_time) unless self.do_not_sleep
      end
    end

    def begin_animation!(options = {}, &block)
      animate!(options, &block)
    end

    def interpolate(first, last, total, i)
      results = []
      first.count.times do |j|
        results[j] = (last[j] - first[j])*i.to_f/total + first[j]
      end
      results
    end

    def capabilities
      @devices.map{|device| device.capabilities}.flatten.uniq
    end

    def points
      @devices.map{|device| device.points.keys}.flatten.uniq
    end

    def method_missing(meth, *args, &block)
      meth_without_bang = meth.to_s.gsub(/!\Z/, "").to_sym

      if points.include? meth
        buffer :point => meth
      elsif points.include? meth_without_bang
        # causes controller.center! to convert to controller.instant!(:point => :center)
        instant! :point => meth_without_bang
      elsif capabilities.include? meth
        buffer meth => args.first
      elsif capabilities.include? meth_without_bang
        instant! meth_without_bang => args.first
      else
        super # You *must* call super if you don't handle the
              # method, otherwise you'll mess up Ruby's method
              # lookup.
      end
    end
  end
end
