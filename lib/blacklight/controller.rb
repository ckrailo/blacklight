# -*- encoding : utf-8 -*-
#
# Filters added to this controller apply to all controllers in the hosting application
# as this module is mixed-in to the application controller in the hosting app on installation.
module Blacklight::Controller 

  extend ActiveSupport::Concern
  include Blacklight::LegacyControllerMethods
  
  included do
    include Blacklight::SearchFields
    include ActiveSupport::Callbacks

    # now in application.rb file under config.filter_parameters
    # filter_parameter_logging :password, :password_confirmation 
    helper_method :current_user_session, :current_user, :current_or_guest_user
    after_filter :discard_flash_if_xhr    

    # handle basic authorization exception with #access_denied
    rescue_from Blacklight::Exceptions::AccessDenied, :with => :access_denied
    
    helper_method :request_is_for_user_resource?
    
    # extra head content
    helper_method :has_user_authentication_provider?
    helper_method :blacklight_config


    # This callback runs when a user first logs in

    define_callbacks :logging_in_user
    set_callback :logging_in_user, :before, :transfer_guest_user_actions_to_current_user

  end

  def default_catalog_controller
    CatalogController
  end

  def blacklight_config
    default_catalog_controller.blacklight_config
  end
   
    protected

    # Returns a list of Searches from the ids in the user's history.
    def searches_from_history
      session[:history].blank? ? [] : Search.where(:id => session[:history]).order("updated_at desc")
    end
    
    #
    # Controller and view helper for determining if the current url is a request for a user resource
    #
    def request_is_for_user_resource?
      request.env['PATH_INFO'] =~ /\/?users\/?/
    end



    # Should be provided by authentication provider
    # def current_user
    # end
    # def current_or_guest_user
    # end

    # Here's a stub implementation we'll add if it isn't provided for us
    def current_or_guest_user
      if defined? super
        super
      else
        current_user if has_user_authentication_provider?
      end
    end
    alias_method :blacklight_current_or_guest_user, :current_or_guest_user

    ##
    # We discard flash messages generated by the xhr requests to avoid
    # confusing UX.
    def discard_flash_if_xhr
      flash.discard if request.xhr?
    end

    ##
    #
    #
    def has_user_authentication_provider?
      respond_to? :current_user
    end           

    def require_user_authentication_provider
      raise ActionController::RoutingError.new('Not Found') unless has_user_authentication_provider?
    end

    ##
    # When a user logs in, transfer any saved searches or bookmarks to the current_user
    def transfer_guest_user_actions_to_current_user
      return unless respond_to? :current_user and respond_to? :guest_user and current_user and guest_user
      current_user_searches = current_user.searches.pluck(:query_params)
      current_user_bookmarks = current_user.bookmarks.pluck(:document_id)

      guest_user.searches.reject { |s| current_user_searches.include?(s.query_params)}.each do |s|
        current_user.searches << s
        s.save!
      end

      guest_user.bookmarks.reject { |b| current_user_bookmarks.include?(b.document_id)}.each do |b|
        current_user.bookmarks << b
        b.save!
      end

      # let guest_user know we've moved some bookmarks from under it
      guest_user.reload if guest_user.persisted?
    end

    ##
    # To handle failed authorization attempts, redirect the user to the 
    # login form and persist the current request uri as a parameter
    def access_denied
      # send the user home if the access was previously denied by the same
      # request to avoid sending the user back to the login page
      #   (e.g. protected page -> logout -> returned to protected page -> home)
      redirect_to root_url and flash.discard and return if request.referer and request.referer.ends_with? request.fullpath

      redirect_to root_url and return unless has_user_authentication_provider?

      redirect_to new_user_session_url(:referer => request.fullpath)
    end
  
end

