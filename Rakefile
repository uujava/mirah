# Copyright (c) 2010-2014 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
begin
  require 'bundler/setup'
rescue LoadError
  puts "couldn't load bundler. Check your environment."
end
require 'rake'
require 'rake/testtask'
require 'rubygems'
require 'rubygems/package_task'
require 'java'
require 'jruby/compiler'
require 'ant'

#TODO update downloads st build reqs that are not run reqs go in a different dir
# put run reqs in javalib
# final artifacts got in dist

version_major=ENV["MIRAH_VERSION_MAJOR"] || "0.1.5"
version_minor=ENV["MIRAH_VERSION_MINOR"] || "dev"
version_full="#{version_major}.#{version_minor}"

# this definition ensures that the bootstrap tasks will be completed before
# building the .gem file. Otherwise, the gem may not contain the jars.
task :gem => 'dist/mirahc.jar'

# depends on dist/mirahc.jar
spec = Gem::Specification.load('mirah.gemspec')
spec.version = version_full

Gem::PackageTask.new spec do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

task :default => :new_ci

desc "run new backend ci"
task :new_ci => [:new_ci_jar, :test]

task :new_ci_jar => ['dist/mirah-parser.jar', 'dist/mirahc3.jar'] do
  puts "using dist/mirahc3.jar for tests"
  #dist/mirahc.jar jar loaded by mirah.gemspec when  running test as forked Rake application
  rm 'dist/mirahc.jar'
  cp 'dist/mirahc3.jar', 'dist/mirahc.jar'
end

def run_tests tests
  results = tests.map do |name|
    begin
      Rake.application[name].invoke
    rescue Exception => ex
      puts "test: #{name} failed: #{ex} #{ex.backtrace.join "\n"}"
    end
  end

  tests.zip(results).each do |name, passed|
    unless passed
      puts "Errors in #{name}"
    end
  end
  fail if results.any?{|passed|!passed}
end

desc "run full test suite"
task :test do
  run_tests ['test:parser', 'test:core', 'test:plugins', 'test:jvm', 'test:artifacts' ]
end

Rake::TestTask.new :single_test  => :compile do |t|
  t.libs << 'test'
  t.test_files = FileList["test/single_test.rb"]
end

namespace :test do

  desc "run parser tests"
  Rake::TestTask.new :parser do |t|
    t.test_files = FileList["mirah-parser/test/**/test*.rb"]
  end

  desc "run the core tests"
  Rake::TestTask.new :core do |t|
    t.libs << 'test'
    t.test_files = FileList["test/core/**/*test.rb"]
    java.lang.System.set_property("jruby.duby.enabled", "true")
  end

  desc "run tests for plugins"
  Rake::TestTask.new :plugins do |t|
    t.libs << 'test'
    t.test_files = FileList["test/plugins/**/*test.rb"]
    java.lang.System.set_property("jruby.duby.enabled", "true")
  end

  desc "run the artifact tests"
  Rake::TestTask.new :artifacts do |t|
    t.libs << 'test'
    t.test_files = FileList["test/artifacts/**/*test.rb"]
  end


  desc "run jvm tests"
  task :jvm => 'test:jvm:all'

  namespace :jvm do
    task :test_setup =>  [:clean_tmp_test_classes, :build_test_fixtures]

    desc "run jvm tests using the new self hosted backend"
    task :all do
      run_tests ["test:jvm:rest", "test:jvm:mirrors"]
    end

    desc "run tests for mirror type system"
    Rake::TestTask.new :mirrors do |t|
      t.libs << 'test'
      t.test_files = FileList["test/mirrors/**/*test.rb"]
    end

    Rake::TestTask.new :rest  => :test_setup do |t|
      t.libs << 'test' << 'test/jvm'
      t.ruby_opts.concat ["-r", "new_backend_test_helper"]
      t.test_files = FileList["test/jvm/**/*test.rb"]
    end

    Rake::TestTask.new :modifiers  => :test_setup do |t|
      t.libs << 'test' << 'test/jvm'
      t.ruby_opts.concat ["-r", "new_backend_test_helper"]
      t.test_files = FileList["test/jvm/**/modifiers_test.rb"]
    end

  end
end

task :clean_tmp_test_classes do
  FileUtils.rm_rf "tmp_test/test_classes"
  FileUtils.mkdir_p "tmp_test/test_classes"
end



task :build_test_fixtures => 'tmp_test/fixtures/fixtures_built.txt'
directory 'tmp_test/fixtures'

file 'tmp_test/fixtures/fixtures_built.txt' => ['tmp_test/fixtures'] + Dir['test/fixtures/**/*.java'] do

  javac_args = {
      'destdir' => "tmp_test/fixtures",
      'srcdir' => 'test/fixtures',
      'includeantruntime' => false,
      'debug' => true,
      'listfiles' => true
  }
  jvm_version = java.lang.System.getProperty('java.specification.version').to_f

  javac_args['excludes'] = '**/*Java8.java' if jvm_version < 1.8
  ant.javac javac_args

  run_mirahc('test-fixtures', ['dist/mirahc.jar'], 'tmp_test/fixtures', ['dist/mirahc.jar'], Dir['test/fixtures/**/*_fixture.mirah'])

  cp_r 'test/fixtures/META-INF', 'tmp_test/fixtures/META-INF'
  `touch tmp_test/fixtures/fixtures_built.txt`
end

task :init do
  mkdir_p 'dist'
  mkdir_p 'build'
  mkdir_p 'javalib'
end

desc "clean up build artifacts"
task :clean do
  ant.delete 'quiet' => true, 'dir' => 'build'
  ant.delete 'quiet' => true, 'dir' => 'dist'
  rm_rf 'dist'
  rm_rf 'tmp'
  rm_rf 'tmp_test'
  rm_rf 'pkg'
end

desc "clean mirah prev"
task :clean_mirah_prev do
  rm_f 'javalib/mirahc-prev.jar'
end

desc "clean downloaded dependencies"
task :clean_downloads => 'javalib/mirahc-prev.jar' do
  rm_f 'javalib/jruby-complete.jar'
  rm_f 'javalib/asm-5.jar'
  rm_f 'javalib/mirah-asm-5.jar'
  rm_f 'javalib/jarjar.jar'
end

task :compile, [:verbose] => 'dist/mirahc.jar'
task :jvm_backend => 'dist/mirahc.jar'

desc "build backwards-compatible ruby jar"
task :jar,[:verbose] => :compile do |task, args|
  ant.jar 'jarfile' => 'dist/mirah.jar' do
    fileset 'dir' => 'lib'
    fileset 'dir' => 'build'
    fileset 'dir' => '.', 'includes' => 'bin/*'
    zipfileset 'src' => 'dist/mirahc.jar'
    manifest do
      attribute 'name' => 'Main-Class', 'value' => 'org.mirah.MirahCommand'
    end
  end
end

namespace :jar do
  desc "build self-contained, complete ruby jar"
  task :complete => [:jar, 'javalib/mirah-asm-5.jar'] do
    ant.jar 'jarfile' => 'dist/mirah-complete.jar' do
      zipfileset 'src' => 'dist/mirah.jar'
      zipfileset 'src' => 'javalib/mirah-asm-5.jar'
      manifest do
        attribute 'name' => 'Main-Class', 'value' => 'org.mirah.MirahCommand'
      end
    end
  end
end

desc "Build a distribution zip file"
task :zip => 'jar:complete' do
  basedir = "tmp/mirah-#{version_full}"
  mkdir_p "#{basedir}/lib"
  mkdir_p "#{basedir}/bin"
  cp 'dist/mirah-complete.jar', "#{basedir}/lib"
  cp 'distbin/mirah.bash', "#{basedir}/bin/mirah"
  cp 'distbin/mirahc.bash', "#{basedir}/bin/mirahc"
  cp Dir['{distbin/*.bat}'], "#{basedir}/bin/"
  cp_r 'examples', "#{basedir}/examples"
  rm_rf "#{basedir}/examples/wiki"
  cp 'README.md', "#{basedir}"
  cp 'NOTICE', "#{basedir}"
  cp 'LICENSE', "#{basedir}"
  cp 'COPYING', "#{basedir}"
  cp 'History.txt', "#{basedir}"
  sh "sh -c 'cd tmp ; zip -r ../dist/mirah-#{version_full}.zip mirah-#{version_full}/*'"
  rm_rf 'tmp'
end

desc "Build java stub"
task :stub => [:clean_stub, 'dist/mirahc-stub.jar'] do
  ant.jar 'jarfile' => 'dist/mirahc-stub.jar' do
    fileset 'dir' => 'stub'
  end
end
task :clean_stub do
  rm_f 'dist/mirahc-stub.jar'
  rm_rf 'stub'
end

desc "Build all redistributable files"
task :dist => [:gem, :zip]

file_create 'javalib/mirah-asm-5.jar' => :jarjar do
  require 'open-uri'
  puts "Downloading asm-5.jar"
  url = 'https://repo1.maven.org/maven2/org/ow2/asm/asm-all/5.0.4/asm-all-5.0.4.jar'
  open(url, 'rb') do |src|
    open('javalib/asm-5.jar', 'wb') do |dest|
      dest.write(src.read)
    end
  end
  ant.jarjar 'jarfile' => 'javalib/mirah-asm-5.jar' do
    zipfileset 'src' => 'javalib/asm-5.jar'
    _element 'rule', 'pattern'=>'org.objectweb.**', 'result'=>'mirah.objectweb.@1'
  end
end

file_create 'javalib/mirahc-prev.jar' => [:init] do
  require 'open-uri'

  url = ENV['MIRAH_PREV_PATH'] || 'https://github.com/uujava/mirah/releases/download/0.1.5.152/mirahc-0.1.5.152.jar'

  puts "Downloading mirahc-prev.jar from #{url}"

  open(url, 'rb') do |src|
    open('javalib/mirahc-prev.jar', 'wb') do |dest|
      dest.write(src.read)
    end
  end
end

file_create 'javalib/jarjar.jar' => [:init] do
  require 'open-uri'
  puts "Downloading jarjar.jar"
  url = 'https://repo1.maven.org/maven2/com/googlecode/jarjar/jarjar/1.1/jarjar-1.1.jar'
  open(url, 'rb') do |src|
    open('javalib/jarjar.jar', 'wb') do |dest|
      dest.write(src.read)
    end
  end
end

task :jarjar => 'javalib/jarjar.jar' do
  # We use jarjar to do some rewritting of packages in the parser and asm.
  ant.taskdef 'name' => 'jarjar',
              'classpath' => 'javalib/jarjar.jar',
              'classname'=>"com.tonicsystems.jarjar.JarJarTask"
end
def build_jar(new_jar, build_dir)
  # Build the jar
  dist_mirah_parser_jar = mirah_parser_jar_name(new_jar)

  ant.jar 'jarfile' => new_jar do
    fileset 'dir' => build_dir, 'excludes' => 'META-INF/*'
    zipfileset 'src' => 'javalib/mirah-asm-5.jar', 'includes' => 'mirah/objectweb/**/*'
    zipfileset 'src' => dist_mirah_parser_jar
    metainf 'dir' => File.dirname(__FILE__), 'includes' => 'LICENSE,COPYING,NOTICE'
    metainf 'dir' => build_dir, 'includes' => 'META-INF/*'
    manifest do
      attribute 'name' => 'Main-Class', 'value' => 'org.mirah.MirahCommand'
    end
  end
end

desc "create version file from ENV MIRAH_MAJOR_VERSION, MIRAH_MINOR_VERSION"
task :mirah_version => "build/generated/"
file "build/generated/"  do
  genpath = "build/generated/org/mirah"
  mkdir_p genpath
  File.open("#{genpath}/Version.mirah", 'w') do |dest|
       dest.write("package org.mirah
class Version
   attr_reader minor: String
   attr_reader major: String
   VERSION = Version.new('#{version_major}', '#{version_minor}')

   private def initialize(major:String, minor:String)
     @major = major
     @minor = minor
     @str =  major + '-' + minor
   end

   def toString
     @str
   end
  end
")
    end
end

def mirah_parser_jar_name(new_jar)
  number = new_jar.scan(/dist\/mirahc(.*?)\.jar/).first.first
  parser_jar = "dist/mirah-parser#{number}.jar"
  return parser_jar
end

def build_mirah_parser(old_jar, new_jar)
  name = new_jar.gsub /[\.\/]/, '_'

  # Mirah Parser build tasks

  mirah_parser_build_dir = "build/#{name}-parser"
  mirah_parser_jar = "build/#{name}-parser.jar"
  mirah_parser_gen_src = "#{mirah_parser_build_dir}-gen/mirahparser/impl/Mirah.mirah"
  parser_lexer_class = "#{mirah_parser_build_dir}/mirahparser/impl/MirahLexer.class"
  parser_parser_class = "#{mirah_parser_build_dir}/mirahparser/impl/MirahParser.class"
  parser_node_meta_class = "#{mirah_parser_build_dir}/org/mirahparser/ast/NodeMeta.class"
  parser_node_class = "#{mirah_parser_build_dir}/mirahparser/lang/ast/Node.class"
  parser_meta_src = 'mirah-parser/src/org/mirah/ast/meta.mirah'
  prev_jar = old_jar  #'javalib/mirahc-prev.jar'
  directory "#{mirah_parser_build_dir}/mirah-parser/mirahparser/impl"

  file parser_parser_class => [
           prev_jar,
           mirah_parser_gen_src,
           parser_node_meta_class,
           "#{mirah_parser_build_dir}/mirahparser/impl/MirahLexer.class"
       ] do
    run_mirahc "parser_gen",
               [prev_jar],
               mirah_parser_build_dir,
               [mirah_parser_build_dir,
                'mirah-parser/javalib/mmeta-runtime.jar'],
               [mirah_parser_gen_src]
  end

  file parser_node_meta_class => parser_meta_src do
    run_mirahc "parser_meta",
               [prev_jar],
               mirah_parser_build_dir,
               [prev_jar],
               [parser_meta_src]

  end
  parser_ast_srcs = Dir['mirah-parser/src/mirah/lang/ast/*.mirah'].sort
  file parser_node_class =>
           [prev_jar, parser_node_meta_class] + parser_ast_srcs do
    run_mirahc "parser_ast",
               [prev_jar],
               mirah_parser_build_dir,
               [mirah_parser_build_dir,
                'mirah-parser/javalib/mmeta-runtime.jar'],
               parser_ast_srcs
  end

  parser_java_impl_src = Dir['mirah-parser/src/mirahparser/impl/*.java'].sort

  file parser_lexer_class => parser_java_impl_src do
    ant.javac 'srcDir' => 'mirah-parser/src',
              'destDir' => mirah_parser_build_dir,
              'source' => '1.6',
              'target' => '1.6',
              'debug' => true do
      include 'name' => 'mirahparser/impl/Tokens.java'
      include 'name' => 'mirahparser/impl/MirahLexer.java'
      classpath 'path' => "#{mirah_parser_build_dir}:mirah-parser/javalib/mmeta-runtime.jar"
    end
  end

  file mirah_parser_gen_src => 'mirah-parser/src/mirahparser/impl/Mirah.mmeta' do
    ant.mkdir 'dir' => "#{mirah_parser_build_dir}-gen/mirahparser/impl"
    run_java '-jar', 'mirah-parser/javalib/mmeta.jar',
            '--tpl', 'node=mirah-parser/src/mirahparser/impl/node.xtm',
            'mirah-parser/src/mirahparser/impl/Mirah.mmeta',
            mirah_parser_gen_src
  end

  file mirah_parser_jar => [parser_node_class,
                            parser_node_meta_class,
                            parser_lexer_class,
                            parser_parser_class,
                            :jarjar] do
    ant.jarjar 'jarfile' => mirah_parser_jar do
      fileset 'dir' => mirah_parser_build_dir, 'includes' => 'mirahparser/impl/*.class'
      fileset 'dir' => mirah_parser_build_dir, 'includes' => 'mirahparser/lang/ast/*.class'
      fileset 'dir' => mirah_parser_build_dir, 'includes' => 'org/mirahparser/ast/*.class'
      zipfileset 'src' => 'mirah-parser/javalib/mmeta-runtime.jar'
      _element 'rule', 'pattern'=>'mmeta.**', 'result'=>'org.mirahparser.mmeta.@1'
      manifest do
        attribute 'name'=>"Main-Class", 'value'=>"mirahparser.impl.MirahParser"
      end
    end
  end

  dist_mirah_parser_jar = mirah_parser_jar_name(new_jar)


  file dist_mirah_parser_jar => mirah_parser_jar do
    # Mirahc picks up the built in classes instead of our versions.
    # So we compile in a different package and then jarjar them to the correct
    # one.
    ant.jarjar 'jarfile' => dist_mirah_parser_jar do
      zipfileset 'src' => mirah_parser_jar
      _element 'rule', 'pattern'=>'mirahparser.**', 'result'=>'mirah.@1'
      _element 'rule', 'pattern'=>'org.mirahparser.**', 'result'=>'org.mirah.@1'
      manifest do
        attribute 'name'=>"Main-Class", 'value'=>"mirah.impl.MirahParser"
      end
    end
  end

  # Compile Java parts of the compiler.
end

def bootstrap_mirah_from(old_jar, new_jar, options={})
  optargs = options[:optargs] ||[]

  mirah_srcs = ['build/generated/'] +
      Dir['src/org/mirah/*.mirah'].sort +
      ['src/org/mirah/jvm/types/'] +
      Dir['src/org/mirah/{macros,util}/'] +
      ['src/org/mirah/typer/'] +
      Dir['src/org/mirah/jvm/{compiler,mirrors,model}/'] +
      ['src/org/mirah/tool/'] +
      Dir['src/org/mirah/plugin/*.mirah'].sort

  extensions_srcs = Dir['src/org/mirah/builtins/']

  plugin_srcs = Dir['src/org/mirah/plugin/impl/']

  ant_srcs        =    ['src/org/mirah/ant/compile.mirah']

  dist_mirah_parser_jar = mirah_parser_jar_name(new_jar)

  build_mirah_parser(old_jar, new_jar)

  file new_jar, [:verbose] => mirah_srcs + extensions_srcs + ant_srcs + [old_jar, 'javalib/mirah-asm-5.jar', dist_mirah_parser_jar] + [:mirah_version] do |task, task_args|
    task_args.with_defaults(:verbose => false)
    build_dir = 'build/bootstrap'+new_jar.gsub(/[.-\/]/, '_')
    rm_rf build_dir
    mkdir_p build_dir
    mkdir_p "#{build_dir}/META-INF/services"

    # Compile Java sources
    ant.javac 'source' => '1.6',
              'target' => '1.6',
              'destdir' => build_dir,
              'srcdir' => 'src',
              'includeantruntime' => false,
              'debug' => true,
              'listfiles' => true

    # mirahc needs to be 1.7 or lower

    ant_classpath = $CLASSPATH.grep(/ant/).map{|x| x.sub(/^file:/,'')}
    default_class_path = [ dist_mirah_parser_jar, "javalib/mirah-asm-5.jar", build_dir]
    build_class_path = [dist_mirah_parser_jar, "javalib/mirah-asm-5.jar", build_dir]

    # process all sources with old_jar
    build_class_path = options[:use_old_jar] ? [old_jar] : build_class_path

    optargs += ['--jvm', build_version]

    report = Measure.measure do |x|
      x.report "Compile Mirah core" do
        args = task_args[:verbose] == 'true' ? ['-V'] : []
        run_mirahc("core-#{old_jar}", [build_dir, old_jar], build_dir, default_class_path, mirah_srcs,  *(args + optargs))
      end

      x.report "compile ant stuff" do
        ant_sources = ['src/org/mirah/ant']
        run_mirahc("ant-#{old_jar}", build_class_path, build_dir, build_class_path+ant_classpath, ant_sources, *optargs)
      end

      x.report "compile extensions" do
        args = task_args[:verbose] == 'true' ? ['-V'] : []
        run_mirahc("ext-#{old_jar}", build_class_path, build_dir, build_class_path, extensions_srcs, *(args + optargs))
        cp_r 'src/org/mirah/builtins/services', "#{build_dir}/META-INF"
      end

      x.report "compile plugins" do
        args = task_args[:verbose] == 'true' ? ['-V'] : []
        run_mirahc("plugins-#{old_jar}", build_class_path, build_dir, build_class_path, plugin_srcs, *(args + optargs ))
        cp_r 'src/org/mirah/plugin/impl/services', "#{build_dir}/META-INF"
      end

      x.report "build jar" do
        build_jar(new_jar, build_dir)
      end
    end

    report.print
  end

end

bootstrap_mirah_from('javalib/mirahc-prev.jar', 'dist/mirahc.jar')
bootstrap_mirah_from('dist/mirahc.jar', 'dist/mirahc2.jar')
bootstrap_mirah_from('dist/mirahc2.jar', 'dist/mirahc3.jar')
bootstrap_mirah_from('javalib/mirahc.jar', 'dist/mirahc-stub.jar', {:optargs => ['-skip-compile','-plugins', 'stub:stub|+pl'], :use_old_jar => true})


def build_version
  build_version = java.lang.System.getProperty('java.specification.version')
  if build_version.to_f > 1.7
    build_version = '1.7'
  end
  build_version
end

def run_java(*args)
  sh 'java', *args
  unless $?.success?
    exit $?.exitstatus
  end
end

def run_mirahc(step, mirahc_jar, dest_dir, compile_class_path, source_path, *args)
  file_name = step.gsub /[\/\\]/, '_'
  all_args =  compile_class_path.empty? ? [] : ['-classpath', compile_class_path.join(File::PATH_SEPARATOR)]
  all_args +=  args + source_path
  run_java '-Xms712m', '-Xmx712m', '-XX:+PrintGC','-XX:+PrintGCDetails','-XX:+PrintGCDateStamps',"-Xloggc:build/#{file_name}_gc.log",
           '-cp', mirahc_jar.join(File::PATH_SEPARATOR), 'org.mirah.MirahCommand',
           '-d', dest_dir, *all_args
end

class Measure

  def initialize
    @measures =[]
  end

  def self.measure
    report = Measure.new
    yield report
    return report
  end

  def report name
    start = Time.now
    yield self
    @measures << [name, Time.now - start]
  end

  def print
    total = 0
    @measures.each do |m|
      total += m[1]
      puts "#{m.join ': '}sec"
    end
    puts "Total time: #{total}sec"
  end
end
