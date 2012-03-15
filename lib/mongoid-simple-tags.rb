module Mongoid
  module Document
    module Taggable
      def self.included(base)
        base.class_eval do |klass|
          klass.field :author_tags, :type => Array, :default => []
          klass.field :recipient_tags, :type => Array, :default => []
          klass.index :author_tags
          klass.index :recipient_tags
          
          
          klass.send :after_save, :rebuild_tags
        
          include InstanceMethods
          extend ClassMethods
          
        end
      end
      
      module InstanceMethods
        def author_tag_list=(tags)
          self.author_tags = tags.split(",").collect{ |t| t.strip }.delete_if{ |t| t.blank? }
        end
        def recipient_tag_list=(tags)
          self.recipient_tags = tags.split(",").collect{ |t| t.strip }.delete_if{ |t| t.blank? }
        end

        def author_tag_list
          self.author_tags.join(",") if author_tags
        end
        def recipient_tag_list
          self.recipient_tags.join(",") if recipient_tags
        end
        
        def tags
          (author_tags + recipient_tags).uniq
        end
        
        protected
          def rebuild_tags
            self.collection.map_reduce(
              "function() { if(this.author_tags) this.author_tags.forEach(function(t){ emit(t, 1); }); }",
              "function(key,values) { var count = 0; values.forEach(function(v){ count += v; }); return count; }",
              { :out => 'author_tags' }
            )
            
            self.collection.map_reduce(
              "function() { if(this.recipient_tags) this.recipient_tags.forEach(function(t){ emit(t, 1); }); }",
              "function(key,values) { var count = 0; values.forEach(function(v){ count += v; }); return count; }",
              { :out => 'recipient_tags' }
            )
          end
      end
 

      module ClassMethods
        
        def all_tags(opts={})
          tags = Mongoid.master.collection('tags')
          opts.merge(:sort => ["_id", :desc]) unless opts[:sort]
          tags.find({}, opts).to_a.map!{|item| { :name => item['_id'], :count => item['value'].to_i } }
        end

        def scoped_tags(options={})
          map = <<-MAP
            function() { 
              if(this.tags) {
                this.tags.forEach( function(t) {
                    emit(t, 1)
                })
              } 
            }
          MAP

          reduce = <<-REDUCE
            function(key,values) { 
              var count = 0 
              values.forEach(function(v){ 
                count += v
              }) 
              return count
            }
          REDUCE

          scope = {}
          options.each do |key, value|
            scope[key] = {'$in' => [value]} 
          end
          
          results = self.collection.map_reduce(
            map,
            reduce,
            :out => "scoped_tags",
            :query => scope
          )
          results.find().to_a.map{ |item| { :name => item['_id'], :count => item['value'].to_i } }
        end
        
        def author_tagged_with(tags)
          tags = [tags] unless tags.is_a? Array
          criteria.in(:author_tags => tags).to_a
        end
        def recipient_tagged_with(tags)
          tags = [tags] unless tags.is_a? Array
          criteria.in(:recipient_tags => tags).to_a
        end
      end
      
    end
  end
end