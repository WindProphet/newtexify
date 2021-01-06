#!/usr/bin/env ruby

require 'securerandom'
require 'open3'
require 'tmpdir'

module Texify
  
  EngineList = %w[
    TeX
    plainTeX
    LaTeX
    XeLaTeX
    XeTeX
    conTeXt
  ]
  
  class Instance
    def initialize(opt, on = nil)
      @on = on ? on : TexifyInfo.method(:on)
      @options = opt.select { |k, v| not [:dir, :content, :files, :file].include? k }
      @dir = if opt[:dir]
        raise NotDirectoryError, opt[:dir] unless File.directory? opt[:dir]
        File.absolute_path opt[:dir]
      else
        dir = Dir.methods.include?(:mktmpdir) ? 
          Dir.mktmpdir :
          (d = "/tmp/Texify_#{SecureRandom.alphanumeric}"; Dir.mkdir(d); d)
        @on.call "Texify temp directory in #{dir}"
        @options[:tmpdir] = dir
        dir
      end
      @file = if opt[:dir]
        nil
      elsif opt[:content]
        @content = opt[:content]
        nil
      else
        raise FileNotExistError, opt[:file] unless File.exist? opt[:file]
        opt[:file]
      end
    end
    
    def directory
      @dir
    end
    
    def findmainfile
      dir = @dir
      
      loop do
        fl = Dir.glob(File.join(dir, '*.tex'))
        if fl.count > 0
          sfl = fl.select {|f| File.basename(f) == (@options[:mainfile] or 'main.tex')}
          if sfl.count > 0
            @mainfile = sfl.first
            break
          else
            raise MainTexFileUncertainError if sfl.count > 1
            @mainfile = fl.first
          end
        else
          dl = Dir.glob(File.join(dir, '*/')).select {|f| not File.basename(f) =~ /^[\._]/}
          raise MainTexFileUncertainError if dl.count == 0 or dl.count > 1
          dir = dl.first
        end
      end
      
      @rundir = dir
      @on.call "TeX main select to #{@mainfile.sub(File.join(@dir, '/'), '')}"
    end
    
    def prepare
      if @content
        @mainfile = File.join(@dir, 'main.tex')
        File.open(@mainfile, 'w') {|f| f.write(@content)}
        @on.call "Copy content to #{@mainfile}"
      elsif @file
        if File.directory? @file
          system "cp -r '#{@file}' '#{@dir}'", :out => File::NULL
          self.findmainfile
        else
          magic_number = File.open(@file, 'r') {|f| f.read(4)}
          if magic_number == "PK\x03\x04"
            system "unzip '#{@file}' -d '#{@dir}'", :out => File::NULL
            @on.call "Input file is a zip file"
            self.findmainfile
          else
            @mainfile = File.join(@dir, 'main.tex')
            system "cp '#{@file}' '#{@mainfile}'", :out => File::NULL
            @on.call "Copy content to #{@mainfile}"
          end
        end
      else
        self.findmainfile
      end
    end
    
    def fork
      @rundir = @dir unless @rundir
      @on.call "Texify run on #{@rundir}"
      begin
        self.make if @options[:makefile]
        if not @options[:bib]
          self.render
          self.render if not @options[:one]
        else
          self.render
          self.bibtex
          self.render
          self.render if not @options[:one]
        end
      rescue RenderError => e
        @error = true
        raise
      end
      if @options[:output]
        if @options[:output] == '-' or @options[:output] == '/dev/stdout'
          system "cat '#{@pdfoutfile}'"
        elsif @options[:output].start_with?('/dev')
          system "cat '#{@pdfoutfile}' >> #{@options[:output]}"
        else
          system "cp '#{@pdfoutfile}' '#{@options[:output]}'", :out => File::NULL
        end
      end
      self.clean if @options[:clean]
    end
    
    def errorlog
      if @error
        @log
      else
        ''
      end
    end
    
    def run
      self.prepare
      self.fork
    end
    
    def preview
      system "open #{@options[:preview_app] ? "-a '#{@options[:preview_app]}'" : ''} '#{@pdfoutfile}'" if @pdfoutfile
    end
    
    def clean
      if @options[:tmpdir]
        @on.call "rm -rf #{@options[:tmpdir]}"
        system "rm -rf #{@options[:tmpdir]}"
      end
    end
    
    def opts
      o = []
      o.push "--shell-escape" if @options[:shellescape]
      o
    end
    
    def make
      args = ['make']
      args.push @options[:makefile_options] if @options[:makefile_options]
      Open3.popen3(*args, :chdir => @rundir) do |stdin, stdout, stderr, wait_thr|
        @on.call args.join(' ')
        stdin.close
        @log = stdout.read
        exit_status = wait_thr.value
        raise RenderError, args if exit_status != 0
        exit_status
      end
    end
    
    def render
      raise InvaildRendererError, @options[:engine] unless EngineList.map(&:downcase).include? @options[:engine].downcase
      args = [
        @options[:engine].downcase,
        '-halt-on-error',
        *self.opts,
        @mainfile
      ]
      @pdfoutfile = File.join(File.dirname(@mainfile), File.basename(@mainfile, '.tex') + '.pdf')
      Open3.popen3(*args, :chdir => @rundir) do |stdin, stdout, stderr, wait_thr|
        @on.call args.join(' ')
        stdin.close
        @log = stdout.read
        exit_status = wait_thr.value
        raise RenderError, args if exit_status != 0
        exit_status
      end
    end
    
    def bibtex
      args = ['bibtex', File.basename(@mainfile, '.tex')]
      Open3.popen3(*args, :chdir => @rundir) do |stdin, stdout, stderr, wait_thr|
        @on.call args.join(' ')
        stdin.close
        @log = stdout.read
        exit_status = wait_thr.value
        raise RenderError, args if exit_status != 0
        exit_status
      end
    end
  end
  
  module TexifyInfo
    module_function
    
    def warn(str)
      "\x1b[33;1m#{str}\x1b[0m"
    end
  
    def stress(str)
      "\x1b[1m#{str}\x1b[0m"
    end
  
    def error(str)
      "\x1b[31;1m#{str}\x1b[0m"
    end
  
    def on(str)
      STDERR.puts "\x1b[32;1m==> \x1b[30;1m#{str}\x1b[0m"
    end
  end
  
  class NotDirectoryError < RuntimeError
    def initialize(file = nil)
      super "Not a directory#{file and " - #{file}"}"
    end
  end
  
  class MainTexFileUncertainError < RuntimeError
    def initialize(file = nil)
      super "Cannot Fonud a certain Main TeX File#{file and " - #{file}"}"
    end
  end
  
  class InvaildRendererError < RuntimeError
    def initialize(tex)
      super "Renderer #{tex} is not a vaild program"
    end
  end
  
  class FileNotExistError < Errno::ENOENT; end
  
  class RenderError < RuntimeError
    def initialize(cmd)
      super "Texify Error - #{cmd.join(' ')}"
    end
  end
  
  module_function
  
  def fromOptions(opt)
    o = opt.select { |k, v| not [:files].include? k }
    o[:file] = opt[:files] == [] ? nil : opt[:files].first
    Instance.new o
  end
  
end

if __FILE__ == $0
  require 'optparse'
  
  options = {
    :engine => 'LaTeX',
    :type => 'PDF',
    :preview_app => 'Preview',
  }
  
  # load resource file
  if File.exist? "#{ENV['HOME']}/.newtexifyrc"
    # resource file ~/.newtexifyrc
    #
    # engine = XeLaTeX
    # output_type = PDF

    File.open("#{ENV['HOME']}/.newtexifyrc").readlines.map do |pref|
      unless pref =~ /^(?:([\w\s]+)=(.*?))?(#.*?)?$/
        STDERR.puts "Resource file load error and exit"
        STDERR.puts "error parse: #{pref}"
        exit
      end
      next unless $1
      prop = $1.strip.downcase
      value = $2.strip
      case prop
      when 'engine' then options[:engine] = value
      when 'output_type' then options[:type] = value
      else
        options[prop.to_sym] = value
      end
    end
  end
  
  OptionParser.new do |opts|
    opts.banner = "Usage newtexify.rb [options] [file]"
    opts.separator ""
    
    opts.on "-e", "--engine [ENGINE]", "Choose TeX type engine",
                                     "default engine is #{options[:engine]}" do |engine|
      engine_list = %w[
        TeX
        plainTeX
        LaTeX
        XeLaTeX
        XeTeX
        conTeXt
      ]
      if engine_list.map(&:downcase).grep(engine.to_s.downcase).empty?.!
        options[:engine] = engine.downcase
        options[:force_engine] = true
      else
        STDERR.puts "engine selection must be in #{engine_list.map{|e| "\x1b[1m#{e}\x1b[0m"}.join ', '}"
        STDERR.puts "engine be set to default value \x1b[1m#{options[:engine]}\x1b[0m"
      end
    end
    
    opts.separator ""
    
    opts.on "-t", "--type [TYPE]", "Select output type",
                                 "default output type is #{options[:type]}" do |type|
      output_type_list = %w[PDF DVI PS]
      type = 'ps' if type.to_s.downcase == 'postscript'
      if output_type_list.grep(type.to_s.upcase).empty?.!
        options[:output_type] = type.downcase
      else
        STDERR.puts "output type selection must be in #{output_type_list.map{|e| "\x1b[1m#{e}\x1b[0m"}.join ', '}"
        STDERR.puts "output type be set to default value \x1b[1m#{options[:type]}\x1b[0m"
      end
    end
    
    opts.separator ""
    
    opts.on "-1", "--[no-]onetime", "only compile onetime" do |one|
      options[:one] = one
    end
    
    opts.on "-b", "--[no-]bibtex", "use BibTeX" do |bib|
      options[:bib] = bib
    end
    
    opts.on "-m", "--main FILE", "set main TeX file" do |file|
      options[:mainfile] = file
    end
    
    opts.on "-M", "--makefile [option]", "run make before compiling" do |make|
      options[:makefile] = true
      options[:makefile_options] = make
    end
    
    opts.on "-c", "--[no-]clean", "clean cache" do |clean|
      options[:clean] = clean
    end
    
    opts.on "-o", "--output FILE", "set output filename" do |output|
      options[:output] = output
    end
    
    opts.on "-p", "--preview", "show preview" do |p|
      options[:preview] = p
    end
    
    opts.on "--[no-]shell-escape", "disable/enable \\write18{SHELL COMMAND}" do |shell_esc|
      options[:shellescape] = shell_esc
    end
    
    opts.on "-d", "--dir DIR" do |dir|
      options[:dir] = dir
    end
    
    opts.on "-h", "--help", "Prints this help" do
      puts opts
      exit
    end
    
    opts.separator ""
  end.parse!
  options[:files] = ARGV.clone
  if options[:files].include?("-") or options[:files].empty? and not options[:dir]
    options[:content] = STDIN.read
  end
  filecount = ((options[:dir] != nil ? 1 : 0) +
               (options[:files].select{|e|e!='-'}.count) +
               (options[:content] != nil ? 1 : 0))
  if filecount > 1
    STDERR.puts "#{File.basename($0)} only receive one input"
    exit 1
  end
  options[:preview] = true unless options[:output]
  t = Texify.fromOptions options
  begin
    t.run
    t.preview if options[:preview]
  rescue Texify::RenderError
    STDERR.print t.errorlog
    exit 1
  end
end