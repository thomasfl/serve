module Serve #:nodoc:
  class Handler < FileTypeHandler #:nodoc:
    extension 'haml', 'erb', 'rhtml', 'html.erb', 'html.haml'
    
    def process(req, res)
      res['content-type'] = content_type
      res.body = parse
    end
    
    def parse
      context = Context.new
      parser = Parser.new(context)
      context.content << parser.parse_file(@script_filename)
      layout = find_layout_for(@script_filename)
      if layout
        parser.parse_file(layout)
      else
        context.content
      end
    end
    
    def find_layout_for(filename)
      root = Dir.pwd
      path = filename[root.size..-1]
      layout = nil
      begin
        path = File.dirname(path)
        l = File.join(root, path, '_layout.haml')
        layout = l if File.file?(l)
      end until layout or path == "/"
      layout
    end
    
    module ERB #:nodoc:
      class Engine #:nodoc:
        def initialize(string, options = {})
          @erb = ::ERB.new(string, nil, '-')
          @erb.filename = options[:filename]
        end
        
        def render(context, &block)
          @erb.result(context.instance_eval { binding })
        end
      end
    end
    
    class Parser #:nodoc:
      attr_accessor :context, :script_filename
      
      def initialize(context)
        @context = context
        @context.parser = self
      end
      
      def parse_file(filename)
        old_script_filename = @script_filename
        @script_filename = filename
        lines = IO.read(filename)
        engine = case File.extname(filename).sub(/^./, '').downcase
          when 'haml'
            require 'haml'
            Haml::Engine.new(lines, :attr_wrapper => '"', :filename => filename)
          when 'erb'
            require 'erb'
            ERB::Engine.new(lines, :filename => filename)
          else
            raise 'extension not supported'
        end
        result = engine.render(context) do |*args|
          context.get_content_for(*args)
        end
        @script_filename = old_script_filename
        result
      end
    end
    
    class Context #:nodoc:
      attr_accessor :content, :parser
      
      def initialize
        @content = ''
      end
      
      # Content_for methods
      
      def content_for(symbol, &block)
        set_content_for(symbol, capture_haml(&block))
      end
      
      def content_for?(symbol)
        !(get_content_for(symbol)).nil?
      end
      
      def get_content_for(symbol = :content)
        if symbol.to_s.intern == :content
          @content
        else
          instance_variable_get("@content_for_#{symbol}")
        end
      end
    
      def set_content_for(symbol, value)
        instance_variable_set("@content_for_#{symbol}", value)
      end
    
      # Render methods
    
      def render(options)
        partial = options.delete(:partial)
        template = options.delete(:template)
        case
        when partial
          render_partial(partial)
        when template
          render_template(template)
        else
          raise "render options not supported #{options.inspect}"
        end
      end
      
      def render_partial(partial)
        render_template(partial, :partial => true)
      end
      
      def render_template(template, options={})
        path = File.dirname(parser.script_filename)
        if template =~ %r{^/}
          template = template[1..-1]
          path = Dir.pwd
        end
        filename = template_filename(File.join(path, template), :partial => options.delete(:partial))
        if File.file?(filename)
          parser.parse_file(filename)
        else
          raise "File does not exist #{filename.inspect}"
        end
      end
      
      private
      
        def template_filename(name, options)
          path = File.dirname(name)
          template = File.basename(name)
          template = "_" + template if options.delete(:partial)
          template += extname(parser.script_filename) unless name =~ /\.[a-z]{3,4}$/
          File.join(path, template)
        end
        
        def extname(filename)
          /(\.[a-z]{3,4}\.[a-z]{3,4})$/.match(filename)
          $1 || File.extname(filename) || ''
        end
    end
  end
end