require 'rails/generators'
require File.expand_path('../utils', __FILE__)
require File.expand_path('../migrations', __FILE__)

# inspired by https://github.com/sferik/rails_admin/blob/master/lib/generators/rails_admin/install_generator.rb

module Pistoncms
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("../templates", __FILE__)
    include Rails::Generators::Migration
    include Generators::Utils::InstanceMethods
    extend Generators::Utils::ClassMethods
    include Generators::Migrations

    class_option :skip_devise, :type => :boolean, :aliases => '-D',
      :desc => "Skip installation and setup of devise gem."
    argument :_model_name, :type => :string, :required => false, :desc => "Devise user model name"
    argument :_namespace, :type => :string, :required => false, :desc => "Pistoncms url namespace"
    desc "Pistoncms installation generator"

    def install
      routes = File.open(Rails.root.join("config/routes.rb")).try :read
      initializer = (File.open(Rails.root.join("config/initializers/pistoncms.rb")) rescue nil).try :read

      display "Hello, Pistoncms installer will help you set things up!", :magenta
      display "I need to work with Devise, let's look at a few things first:"

      if options[:skip_devise]
        display "Skipping devise installation..."
      else
        display "Checking for a current installation of devise..."
        unless defined?(Devise)
          display "Adding devise gem to your Gemfile:"
          append_file "Gemfile", "\n", :force => true
          gem 'devise'
          Bundler.with_clean_env do
            run "bundle install"
          end
        else
          display "Found it!"
        end
        unless File.exists?(Rails.root.join("config/initializers/devise.rb"))
          display "Looks like you don't have devise installed! We'll install it for you:"
          generate "devise:install"
        else
          display "Looks like you've already installed it, good!"
        end
      end

      namespace = ask_for("Where do you want to mount pistoncms?", "", _namespace)
      gsub_file "config/routes.rb", /mount Pistoncms::Engine => \'\/.+\', :as => \'pistoncms\'/, ''
      route("mount Pistoncms::Engine => '/#{namespace}', :as => 'pistoncms'")

      unless options[:skip_devise]
        unless routes.index("devise_for")
          model_name = ask_for("What would you like the user model to be called?", "user", _model_name)
          display "Now setting up devise with user model name '#{model_name}':"
          generate "devise", model_name
        else
          display "And you already set it up, good! We just need to know about your user model name..."
          guess = routes.match(/devise_for +:(\w+)/)[1].try(:singularize)
          display("We found '#{guess}' (should be one of 'user', 'admin', etc.)")
          model_name = ask_for("Correct Devise model name if needed.", guess, _model_name)
          unless guess == model_name
            display "Now setting up devise with user model name '#{model_name}':"
            generate "devise", model_name
          else
            display "Ok, Devise looks already set up with user model name '#{model_name}':"
          end
        end
      end

      display "Now you'll need an initializer..."

      @current_user_method = model_name ? "current_#{model_name.to_s.underscore}" : ""
      @model_name = model_name || '<your user class>'
      unless initializer
        template "initializer.erb", "config/initializers/pistoncms.rb"
      else
        display "You already have a config file. You're updating, heh? I'm generating a new 'pistoncms.rb.example' that you can review."
        template "initializer.erb", "config/initializers/pistoncms.rb.example"
        config_tag = initializer.match(/Pistoncms\.config.+\|(.+)\|/)[1] rescue nil
        if config_tag
          if initializer.index(::Regexp.new("#{config_tag}\.current_user_method.?\{.+?\}"))
            display "current_user_method found and updated with '#{@current_user_method}'", :green
            gsub_file Rails.root.join("config/initializers/pistoncms.rb"), ::Regexp.new("#{config_tag}\.current_user_method.?\{.+?\}"), "#{config_tag}.current_user_method { #{@current_user_method} }"
          else
            display "current_user_method not found. Added one with '#{@current_user_method}'!", :yellow
            insert_into_file Rails.root.join("config/initializers/pistoncms.rb"), "\n\n  #{config_tag}.current_user_method { #{@current_user_method} } #auto-generated", :after => /^Pistoncms\.config.+$/
          end
        else
          display "Couldn't parse your config file: current_user_method couldn't be updated", :red
        end
      end
      display "Lets copy over piston's migration files"
      run_migrations
      display "Job's done: customize devise, migrate, start your server and visit '/#{namespace}'!", :magenta

    end

  end
end