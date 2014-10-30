#!/usr/bin/env ruby

require 'fileutils'


# TODO: These should be passed in as env vars. When we're in a POD, make sure to do this.
# WORKAROUND: ^^
OO_ENV = 'stg'
OO_CTR_TYPE = 'proxy'
HOSTGROUPS = ['STG Environment']
TEMPLATES = ['Template OpenShift Proxy Ctr']
CTR_NAME = "ctr-#{OO_CTR_TYPE}-#{OO_ENV}-#{ENV['container_uuid'][0..6]}"


CTR_CONFIG_FLAG = '/shared/var/run/ctr-ipc/flag/ctr_configured'


class Start
  def self.wait_for_ctr_configured
    while ! File.exist?(CTR_CONFIG_FLAG)
      puts "Sleeping 10 seconds, waiting for #{CTR_CONFIG_FLAG}"
      sleep 10
    end
  end

  def self.add_to_zabbix
    # Need to do this as a separate script because /usr/local gets changed after this script starts.
    # FIXME: we can change this once we aren't using the puppet container anymore
    cmd = "/register-with-zabbix.rb --name #{CTR_NAME}"
    cmd += ' ' + HOSTGROUPS.collect() { |a| "--hostgroup '#{a}'" }.join(' ')
    cmd += ' ' + TEMPLATES.collect() { |a| "--template '#{a}'" }.join(' ')
    puts "Running: #{cmd}"
    system(cmd)
    raise "failed" unless $?.exitstatus == 0
  end

  def self.setup_shared_dirs
    puts '_'
    ['/usr/local', '/etc/openshift', '/var/lib/haproxy', '/etc/haproxy'].each do |shared_dir|
      puts "Setting up /shared#{shared_dir}..."
      FileUtils.rm_rf(shared_dir)
      FileUtils.ln_s("/shared#{shared_dir}", shared_dir)
    end
    puts '_'
  end

  def self.setup_cron()
    File.open('/etc/crontab', 'a') do |f|
      # FIXME: on failure, this should e-mail, not log to a file. Not sure how best to do that in a 1 service per container way.
      f.write("30 12 * * * root /usr/bin/flock -n /var/tmp/cron-send-cert-expiration.lock -c '/usr/bin/timeout -s9 30s /usr/local/bin/cron-send-cert-expiration.rb --server noc2.ops.rhcloud.com --zbx-host #{CTR_NAME}' &>> /var/log/cron-send-cert-expiration.log\n")
      f.write("*/2 * * * * root /usr/local/bin/cron-send-haproxy-status.rb --server noc2.ops.rhcloud.com --zbx-host #{CTR_NAME} &>> /var/log/cron-send-haproxy-status.log\n")
    end
  end

  def self.exec_cron()
    puts '_'
    puts 'Exec-ing cron'
    puts '-------------'
    puts "Starting cron..."
    exec("/usr/sbin/crond -n")
  end
end

if __FILE__ == $0
  $stdout.sync = true
  $stderr.sync = true

  Start.setup_shared_dirs()
  Start.wait_for_ctr_configured
  Start.add_to_zabbix()
  Start.setup_cron()
  Start.exec_cron()
end