#!/usr/local/bin/ruby

case ENV['ZEPHYR_ENV']
when 'local'
  $app_dev = true
  $app_base_url = "http://local.webapp.com"
  $app_file_path = "/usr/local/www/webapp.com"
when 'dev'
  $app_dev = true
  $app_base_url = "http://dev.webapp.com"
  $app_file_path = "/usr/local/www/dev.webapp.com"
when 'production'
  $app_dev = false
  $app_base_url = "http://www.webapp.com"
  $app_file_path = "/usr/local/www/webapp.com"
end

$LOAD_PATH << $app_file_path + '/lib'
$LOAD_PATH << $app_file_path + '/app'
$LOAD_PATH << $app_file_path + '/'

# Let's supress ruby warnings
$VERBOSE = nil

# Redirect stderr to a log file
$stderr.reopen("/tmp/webapp-error.log", "a")

require 'rubygems'
require 'rack'
require 'log4r'
require 'zephyr'
require 'app'

# Set up logging
$log = Log4r::Logger.new "log"
$log.outputters = Log4r::Outputter.stderr

def test(req)
  r = Rack::Response.new
  r.body = "<p>Testing</p>"
  r.body << "<p>#{req.path_info}</p>"
  r.body << "<p>#{req.script_name}</p>"
  r.body << "<p>#{req.url}</p>"
  r.body << "<p>#{req.query_string}</p>"
  r.finish
end

# Define app
class App
  def call(env)
    begin
      req = Rack::Request.new(env)

      if ENV['ZEPHYR_ENV'] == "local"
        script_name = req.script_name
      else
        script_name = req.path_info
      end

      if Zephyr::Routing.routes.has_key?(script_name)
        mod = Zephyr::Routing.routes[script_name][:mod]
        klass = Zephyr::Routing.routes[script_name][:klass]

        x = Object.const_get(mod).const_get(klass).new(req)
        x.resp.finish
      elsif script_name == '' or script_name == '/'
        # Display ref page
        x = DisplayRefPage.new(req)
        x.resp.finish
      else
        # Display main help page
        #test(req)
        x = Help::View.new(req)
        x.resp.finish
      end
    rescue Exception => e
      $log.info("Error occured while processing request!")
      $log.info("Exception: #{e.message}")
      $log.info("Backtrace: #{e.backtrace.join("\n")}")
      $log.info("Request object: #{req}")
      $log.info("Request path: #{req.path_info}")
      $log.info("Response object: #{x}")
      $log.info("x: #{x}") if defined?(x)

      Zephyr::report_error(e.message, e.backtrace, env)
      Zephyr::show_error_page
    rescue DBI::DatabaseError => e
      $log.info("(in dispatch script) DB error!")
      $log.info("Exception: #{e.message}")
      $log.info("Backtrace: #{e.backtrace}")

      Zephyr::report_error(e.message, e.backtrace)
      Zephyr::show_error_page
    end
  end
end

# Run app
begin
  $log.info("Begin FCGI loop (process ##{Process.pid}).")

  # Connect to DB
  Zephyr::DB.connect
  $log.info("Connected to DB.")

  app = App.new

  Rack::Handler::FastCGI.run(app)
rescue Exception => e
  $log.info("Fatal: Dispatcher dying due to uncaught exception (process ##{Process.pid})!")
  $log.info("Exception: #{e.message}")
  $log.info("Backtrace: #{e.backtrace.join("\n")}")

  Zephyr::report_error(e.message, e.backtrace)
  Zephyr::show_error_page
ensure
  $log.info("Finished FCGI loop (process ##{Process.pid}).")
end
