#!/usr/bin/env ruby

=begin
  You can run this like this (assuming you have made it an executable):
    1) ./kill_bloating_passenger.rb
      This will kill all processess with private dirty RSS > 500 MB
    2) ./kill_bloating_passenger.rb 1024
      This will kill all processess with private dirty RSS > 1024 MB
=end

# Find bloating passengers and kill them gracefully. Run at a suitable interval.
ENV['HTTPD']='httpd'

# minimum memory limit set to 500MB
MEMORY_LIMIT_MB = [(ARGV[0].to_i || 500), 500].max

module PassengerMonitor

  def self.kill_bloating_processes
    ensure_single_process do
      report_map = {
        healthy_processes: 0,
        unhealthy_processes: 0
      }

      # if running from crontab, this command may break
      # and you might want to add the path of `passenger-memory-stats` to the PATH
      # in the crontab.
      # Hint: use `which passenger-memory-stats` to determine the relevant path
      lines = `passenger-memory-stats`.split("\n").select do |line|
        # different versions of passenger have different formats of printing stats
        line.include?('ruby /usr/') ||          # passenger v5.3.5
          line.include?('Passenger RubyApp: /') # passenger v5.1.12
      end

      lines.each do |line|
        parts = line.split
        pid, private_dirty_rss = parts[0].to_i, parts[3].to_f
        puts({pid: pid, private_dirty_rss: private_dirty_rss}.inspect)

        if private_dirty_rss > MEMORY_LIMIT_MB.to_i
          report_map[:unhealthy_processes] += 1
          puts "[#{Time.now}] Found bloater #{pid} with size #{private_dirty_rss.to_s}"
          kill_gracefully pid
          puts "[#{Time.now}] Finished kill attempt. Sleeping for 10 seconds..."
          sleep 10
          kill_forcefully(pid) if running?(pid)
        else
          report_map[:healthy_processes] += 1
        end

      end
      puts "[#{Time.now}] #{report_map.inspect}"
    end
  end

  def self.ensure_single_process
    `mkdir -p /tmp/dev_ops`
    pid_file = "/tmp/dev_ops/passenger_bloating_monitor.pid"
    if File.exists? pid_file
      puts "[#{Time.now}] passenger_bloating_monitor already in progress"
    else
      File.open(pid_file, 'w') { |f| f.puts Process.pid }
      begin
        yield
      ensure
        File.delete pid_file
      end
    end
  end

  def self.kill_gracefully pid
    puts "[#{Time.now}] Killing with SIGUSR1 (graceful)..."
    Process.kill("SIGUSR1", pid)
  end

  def self.kill_forcefully pid
    puts "[#{Time.now}] Killing with TERM (forceful)..."
    Process.kill("TERM", pid)
  end

  def self.running? pid
    begin
      Process.getpgid(pid) != -1
    rescue Errno::ESRCH
      false
    end
  end
end

puts "*" * 80
puts "[#{Time.now}] Starting passenger auto-kill process. Can be fatal."
puts "[#{Time.now}] MEMORY_LIMIT_MB is set to #{MEMORY_LIMIT_MB}"
PassengerMonitor.kill_bloating_processes
puts "[#{Time.now}] Done!"
puts "*" * 80