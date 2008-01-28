# SimplyVersioned 1.0.0
#
# Simple ActiveRecord versioning
# Copyright (c) 2007,2008 Matt Mower <self@mattmower.com>
# Released under the MIT license (see accompany MIT-LICENSE file)
#

module SoftwareHeretics
  
  module ActiveRecord
  
    module SimplyVersioned
      
      class BadOptions < StandardError
        def initialize( keys )
          super( "Keys: #{keys.join( "," )} are not known by SimplyVersioned" )
        end
      end
      
      module ClassMethods
        
        # Marks this ActiveRecord model as being versioned. Calls to +create+ or +save+ will,
        # in future, create a series of associated Version instances that can be accessed via
        # the +versions+ association.
        #
        # Options:
        # * +limit+ - specifies the number of old versions to keep (default = nil, never delete old versions)
        # * +automatic+ - controls whether versions are created automatically (default = true, save versions)
        # * +exclude+ - specify columns that will not be saved (default = [], save all columns)
        #
        # To save a model without creating a new version it is recommended to use with +with_versioning+
        # method rather than changing +versioning_enabled+ for the entire model.
        def simply_versioned( options = {} )
          bad_keys = options.keys - [:keep,:automatic,:exclude]
          raise SimplyVersioned::BadOptions.new( bad_keys ) unless bad_keys.empty?
          
          options.reverse_merge!( {
            :keep => nil,
            :automatic => true,
            :exclude => []
          })
          
          has_many :versions, :order => 'number DESC', :as => :versionable, :dependent => :destroy, :extend => VersionsProxyMethods

          after_save :simply_versioned_create_version
          
          cattr_accessor :simply_versioned_keep_limit
          self.simply_versioned_keep_limit = options[:keep]
          
          cattr_accessor :simply_versioned_save_by_default
          self.simply_versioned_save_by_default = options[:automatic]
          
          cattr_accessor :simply_versioned_excluded_columns
          self.simply_versioned_excluded_columns = Array( options[ :exclude ] ).map( &:to_s )
          
          class_eval do
            def versioning_enabled=( enabled )
              self.instance_variable_set( :@simply_versioned_enabled, enabled )
            end
            
            def versioning_enabled?
              enabled = self.instance_variable_get( :@simply_versioned_enabled )
              if enabled.nil?
                enabled = self.instance_variable_set( :@simply_versioned_enabled, self.simply_versioned_save_by_default )
              end
              enabled
            end
          end
        end

      end

      # Methods that will be defined on the ActiveRecord model being versioned
      module InstanceMethods
        
        # Revert the attributes of this model to their values as of an earlier version.
        #
        # Pass either a Version instance or a version number.
        #
        # options:
        # * +except+ specify a list of attributes that are not restored (default: created_at, updated_at)
        #
        def revert_to_version( version, options = {} )
          options.reverse_merge!({
            :except => [:created_at,:updated_at]
          })
          
          version = if version.kind_of?( Version )
            version
          elsif version.kind_of?( Fixnum )
            self.versions.find_by_number( version )
          end
          
          raise "Invalid version (#{version.inspect}) specified!" unless version
          
          options[:except] = Array( options[:except] ).map( &:to_s )
          
          self.update_attributes( YAML::load( version.yaml ).except( *options[:except] ) )
        end
        
        # Invoke the supplied block passing the receiver as the sole block argument with
        # versioning enabled or disabled depending upon the value of the +enabled+ parameter
        # for the duration of the block.
        #
        # Example:
        # 
        # <tt>
        # thing.with_versioning( params[:should_version] == "yes" ) { save! }
        # </tt>
        def with_versioning( enabled, &block )
          versioning_was_enabled = self.versioning_enabled?
          self.versioning_enabled = enabled
          begin
            block.call( self )
          ensure
            self.versioning_enabled = versioning_was_enabled
          end
        end
        
        # Return +true+ if the model has not been versioned yet.
        def unversioned?
          self.versions.nil? || self.versions.empty?
        end
        
        # Return +true+ if the model has been versioned.
        def versioned?
          !unversioned?
        end
        
        # Returns 0 for unversioned models, 1 for newly created models, and so on.
        def version_number
          if self.unversioned?
            0
          else
            self.versions.current.number
          end
        end
        
        protected
        
        def simply_versioned_create_version #:nodoc:
          if self.versioning_enabled?
            if self.versions.create( :yaml => self.attributes.except( *simply_versioned_excluded_columns ).to_yaml )
              self.versions.clean_old_versions( simply_versioned_keep_limit.to_i ) if simply_versioned_keep_limit
            end
          end
          true
        end
        
      end

      # Methods added to the +versions+ collection of a versioned model.
      module VersionsProxyMethods
        
        # Get the +Version+ instance corresponding to this specified version number for this model instance.
        def get_version( number )
          find_by_number( number )
        end
        alias_method :get, :get_version
        
        # Get the first Version corresponding to this model.
        def first_version
          find( :first, :order => 'number ASC' )
        end
        alias_method :first, :first_version

        # Get the current Version corresponding to this model.
        def current_version
          find( :first, :order => 'number DESC' )
        end
        alias_method :current, :current_version
        
        # If the model instance has more versions than the limit specified, delete all excess older versions.
        def clean_old_versions( versions_to_keep )
          find( :all, :conditions => [ 'number <= ?', self.maximum( :number ) - versions_to_keep ] ).each do |version|
            version.destroy
          end
        end
        alias_method :purge, :clean_old_versions
        
        # Return the Version for this model with the next higher version
        def next_version( number )
          find( :first, :order => 'number ASC', :conditions => [ "number > ?", number ] )
        end
        alias_method :next, :next_version
        
        # Return the Version for this model with the next lower version
        def previous_version( number )
          find( :first, :order => 'number DESC', :conditions => [ "number < ?", number ] )
        end
        alias_method :previous, :previous_version
      end

      def self.included( receiver ) #:nodoc:
        receiver.extend         ClassMethods
        receiver.send :include, InstanceMethods
      end
    
    end
  
  end

end

ActiveRecord::Base.send( :include, SoftwareHeretics::ActiveRecord::SimplyVersioned )
